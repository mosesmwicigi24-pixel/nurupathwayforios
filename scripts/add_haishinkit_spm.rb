#!/usr/bin/env ruby
# Wires the HaishinKit Swift Package (RTMP publish/preview for Nuru Live L3)
# into NuruMember.xcodeproj via the `xcodeproj` gem's object API — this
# project has zero XCRemoteSwiftPackageReference/XCSwiftPackageProductDependency
# entries before this script runs (first-ever SPM dependency), so there is no
# existing entry to copy; this is scripted (not hand-edited) for correctness.
#
# Run once from the repo root:
#   ruby scripts/add_haishinkit_spm.rb
#
# Safe to re-run: it no-ops if a HaishinKit package reference already exists.
require 'xcodeproj'

PROJECT_PATH = File.expand_path('../NuruMember.xcodeproj', __dir__)
REPO_URL = 'https://github.com/HaishinKit/HaishinKit.swift'
VERSION = '2.2.5' # latest stable tag as of this writing (checked via GitHub tags API)
PRODUCTS = %w[HaishinKit RTMPHaishinKit].freeze
TARGET_NAME = 'NuruMember'

project = Xcodeproj::Project.open(PROJECT_PATH)

target = project.targets.find { |t| t.name == TARGET_NAME }
raise "Target #{TARGET_NAME} not found in #{PROJECT_PATH}" unless target

existing = project.root_object.package_references.find do |ref|
  ref.respond_to?(:repositoryURL) && ref.repositoryURL == REPO_URL
end

if existing
  puts "HaishinKit package reference already present (#{existing.uuid}) — nothing to do."
else
  pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg_ref.repositoryURL = REPO_URL
  pkg_ref.requirement = {
    'kind' => 'upToNextMajorVersion',
    'minimumVersion' => VERSION,
  }
  project.root_object.package_references << pkg_ref
  puts "Added XCRemoteSwiftPackageReference #{REPO_URL} @ #{VERSION} (#{pkg_ref.uuid})"

  frameworks_phase = target.frameworks_build_phase

  PRODUCTS.each do |product_name|
    already = target.package_product_dependencies.find { |d| d.product_name == product_name }
    if already
      puts "  Product dependency #{product_name} already attached to #{TARGET_NAME} — skipping."
      next
    end

    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.package = pkg_ref
    dep.product_name = product_name
    target.package_product_dependencies << dep

    build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    build_file.product_ref = dep
    frameworks_phase.files << build_file

    puts "  Attached product #{product_name} to #{TARGET_NAME} (dependency #{dep.uuid}, build file #{build_file.uuid})"
  end
end

project.save
puts "Saved #{PROJECT_PATH}"
