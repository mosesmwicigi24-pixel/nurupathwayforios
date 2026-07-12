// Resources Library — rebuilt from the Figma ResourcesLibraryScreen
// (PathwayScreens.tsx). A cream ScreenShell header (back + "LIBRARY" kicker +
// "Resources" title), a search field, kind filter pills, and a list of resource
// rows (kind-tinted icon, title, author · duration, download). Bound to the real
// GET /growth/resources catalogue. Replaces the old placeholder.
import SwiftUI

struct ResourceRow: Decodable, Sendable, Identifiable {
    let resourceId: String
    let title: String
    let author: String
    let kind: String
    let durationLabel: String
    let url: String?
    var id: String { resourceId }

    private enum CodingKeys: String, CodingKey {
        case resourceId, title, author, kind, durationLabel, url
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        resourceId = try c.decode(String.self, forKey: .resourceId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        author = (try? c.decodeIfPresent(String.self, forKey: .author)) ?? ""
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        durationLabel = (try? c.decodeIfPresent(String.self, forKey: .durationLabel)) ?? ""
        url = try? c.decodeIfPresent(String.self, forKey: .url)
    }
}

// Exact Figma palette (ResourcesLibraryScreen / ScreenShell).
private enum RES {
    static let navy    = Color(hex: 0x0A1628)
    static let gold    = Color(hex: 0xC9A227)
    static let cream   = Color(hex: 0xF4F0E8)
    static let surface = Color(hex: 0xFBF8F1)
    static let border  = Color(hex: 0x0A2540, alpha: 0.08)
    static let kicker  = Color(hex: 0x9A7A2A)
    static let ink2    = Color(hex: 0x59667C)
    static let hint    = Color(hex: 0x74808F)
    static let headA   = Color(hex: 0xF6F4EF)
    static let headB   = Color(hex: 0xEFE8DA)

    struct KindMeta { let label: String; let sf: String; let color: Color; let tint: Color }
    static func meta(_ kind: String) -> KindMeta {
        switch kind {
        // Outline symbols — the Figma tiles use stroked Lucide icons, not filled.
        case "audio":   return KindMeta(label: "Audio",   sf: "headphones",     color: gold,                 tint: Color(hex: 0xFFF4DA))
        case "video":   return KindMeta(label: "Video",   sf: "play.rectangle", color: Color(hex: 0xDC2626), tint: Color(hex: 0xFEE2E2))
        case "article": return KindMeta(label: "Article", sf: "doc.text",       color: Color(hex: 0x16A34A), tint: Color(hex: 0xDCFCE7))
        default:        return KindMeta(label: "Book",    sf: "book",           color: Color(hex: 0x6366F1), tint: Color(hex: 0xEEF2FF))
        }
    }
    static let filters = ["all", "book", "audio", "video", "article"]
}

@MainActor
final class ResourcesViewModel: ObservableObject {
    @Published var items: [ResourceRow] = []
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { items = try await MemberAPI.resources() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load resources." }
        loading = false
    }
}

struct ResourcesLibraryView: View {
    @StateObject private var vm = ResourcesViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var filter = "all"
    @State private var query = ""

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    private var filtered: [ResourceRow] {
        vm.items.filter { (filter == "all" || $0.kind == filter) && (q.isEmpty || $0.title.lowercased().contains(q)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    searchField
                    filterPills
                    content
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 40)
            }
        }
        .background(RES.cream.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.items.isEmpty { await vm.load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: RES.navy).frame(width: 40, height: 40)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(RES.border, lineWidth: 1))
                }.buttonStyle(.pressable)
                Spacer()
                Text("LIBRARY").font(.inter(11, .bold)).kerning(1.98).foregroundStyle(RES.kicker)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            Text("Resources").font(.fraunces(24, .medium)).kerning(-0.72).foregroundStyle(RES.navy).padding(.top, 12)
        }
        .padding(.horizontal, 20).padding(.top, 56).padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [RES.headA, RES.headB], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(RES.gold.opacity(0.13)).frame(width: 224, height: 224).blur(radius: 44).offset(x: 40, y: -70)
            }
        )
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
        .overlay(alignment: .bottom) { Rectangle().fill(RES.border).frame(height: 1) }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Icon(.search, size: 15, color: RES.hint)
            TextField("", text: $query, prompt: Text("Search books, audio, sermons…").foregroundColor(RES.hint))
                .font(.inter(13)).foregroundStyle(RES.navy)
            if !query.isEmpty {
                Button { query = "" } label: { Icon(.x, size: 14, color: RES.hint) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(RES.border, lineWidth: 1))
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RES.filters, id: \.self) { k in
                    let on = filter == k
                    Button {
                        guard filter != k else { return }
                        Haptics.selection()
                        filter = k
                    } label: {
                        Text(k == "all" ? "All" : RES.meta(k).label)
                            .font(.inter(11, .bold)).foregroundStyle(on ? RES.navy : RES.ink2)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(on ? RES.gold : Color.white, in: Capsule())
                            .overlay(Capsule().stroke(on ? Color.clear : RES.border, lineWidth: 1))
                    }.buttonStyle(.pressable)
                }
            }.padding(.horizontal, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        if vm.loading && vm.items.isEmpty {
            // Skeleton rows in the real row anatomy — the list "arrives", it
            // doesn't sit behind a lone spinner.
            VStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { _ in skeletonRow }
            }
        } else if let e = vm.error, vm.items.isEmpty {
            VStack(spacing: 12) {
                Text(e).font(.inter(13)).foregroundStyle(RES.ink2).multilineTextAlignment(.center)
                Button { Haptics.tap(); Task { await vm.load() } } label: {
                    Text("Try again").font(.inter(13, .bold)).foregroundStyle(RES.gold)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.pressable)
            }.frame(maxWidth: .infinity).padding(.top, 44)
        } else if filtered.isEmpty {
            VStack(spacing: 8) {
                Icon(.bookMarked, size: 30, color: RES.ink2.opacity(0.5))
                Text("No resources found").font(.inter(14, .semibold)).foregroundStyle(RES.navy)
                Text("Try a different filter or search term.").font(.inter(12)).foregroundStyle(RES.ink2)
                if !q.isEmpty || filter != "all" {
                    Button { Haptics.tap(); query = ""; filter = "all" } label: {
                        Text("Clear search").font(.inter(12, .bold)).foregroundStyle(RES.gold)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }.frame(maxWidth: .infinity).padding(.top, 44)
        } else {
            VStack(spacing: 8) {
                ForEach(filtered) { r in resourceRow(r) }
            }
        }
    }

    /// Placeholder mirroring resourceRow's exact metrics (48pt tile, two lines).
    private var skeletonRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RES.border)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(RES.border).frame(width: 150, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(RES.border).frame(width: 96, height: 9)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(RES.border, lineWidth: 1))
        .nuruShimmer()
    }

    private func resourceRow(_ r: ResourceRow) -> some View {
        let m = RES.meta(r.kind)
        return Button {
            if let u = r.url, let url = URL(string: u) {
                Haptics.tap()
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: m.sf).font(.system(size: 18)).foregroundStyle(m.color)
                    .frame(width: 48, height: 48)
                    .background(m.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).font(.inter(13, .semibold)).foregroundStyle(RES.navy).lineLimit(1)
                    Text("\(r.author) · \(r.durationLabel)").font(.nCardMeta).foregroundStyle(RES.ink2).lineLimit(1)
                }
                Spacer(minLength: 0)
                Icon(.download, size: 14, color: RES.gold).frame(width: 32, height: 32)
                    .background(RES.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(RES.border, lineWidth: 1))
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(RES.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}
