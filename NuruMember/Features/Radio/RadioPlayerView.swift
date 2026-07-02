// Nuru Radio — the member player over the new backend radio module.
// GET /radio/now-playing returns the LIVE program (hls_url) or the next
// scheduled one (or null). Live streams play via AVPlayer (HLS); pre-recorded
// programs play audio_url. Reactions post to /radio/programs/{id}/react.
import SwiftUI
import AVFoundation

struct RadioProgram: Decodable, Sendable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let category: String
    let speaker: String?
    let artworkUrl: String?
    let scheduledAt: String?
    let status: String
    let isLive: Bool
    let audioUrl: String?
    let hlsUrl: String?
    let peakListeners: Int?

    var streamUrl: URL? {
        if isLive, let h = hlsUrl, let u = URL(string: h) { return u }
        if let a = audioUrl, let u = URL(string: a) { return u }
        return nil
    }
}

struct RadioReactionCounts: Decodable, Sendable { let heart: Int; let amen: Int; let fire: Int }

@MainActor
final class RadioViewModel: ObservableObject {
    @Published var program: RadioProgram?
    @Published var loading = true
    @Published var playing = false
    @Published var counts: RadioReactionCounts?
    private var player: AVPlayer?

    func load() async {
        loading = true
        program = try? await APIClient.shared.get("radio/now-playing", as: RadioProgram?.self) ?? nil
        loading = false
    }

    func togglePlay() {
        guard let url = program?.streamUrl else { return }
        if playing { player?.pause(); playing = false; return }
        if player == nil {
            // Radio must be heard even with the ring switch on silent.
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = AVPlayer(url: url)
        }
        player?.play(); playing = true
    }

    func stop() { player?.pause(); player = nil; playing = false }

    func react(_ kind: String) async {
        guard let id = program?.id else { return }
        struct Body: Encodable { let kind: String }
        counts = try? await APIClient.shared.post("radio/programs/\(id)/react", body: Body(kind: kind), as: RadioReactionCounts.self)
    }
}

struct RadioPlayerView: View {
    @StateObject private var vm = RadioViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x060F1C)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            if vm.loading {
                ProgressView().tint(Nuru.gold)
            } else if let p = vm.program {
                programBody(p)
            } else {
                offAir
            }
        }
        .overlay(alignment: .topLeading) {
            Button { vm.stop(); dismiss() } label: {
                Icon(.x, size: 18, color: .white).frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain).padding(.leading, 16).padding(.top, 8)
        }
        .task { await vm.load() }
        .onDisappear { vm.stop() }
    }

    private func programBody(_ p: RadioProgram) -> some View {
        VStack(spacing: 0) {
            Spacer()
            artwork(p)
            statusPill(p).padding(.top, 20)
            Text(p.title).font(.fraunces(26, .semibold)).kerning(-0.5).foregroundStyle(.white)
                .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 10)
            Text([p.speaker, p.category.capitalized].compactMap { $0 }.joined(separator: " · "))
                .font(.inter(13)).foregroundStyle(.white.opacity(0.6)).padding(.top, 4)
            if let d = p.description, !d.isEmpty {
                Text(d).font(.inter(12)).foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center).lineLimit(2)
                    .padding(.horizontal, 40).padding(.top, 8)
            }
            playButton(p).padding(.top, 28)
            reactions.padding(.top, 26)
            Spacer()
        }
    }

    private func artwork(_ p: RadioProgram) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x16273F), Color(hex: 0x0A1628)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let a = p.artworkUrl, let u = URL(string: a) {
                CachedAsyncImage(url: u) { ph in (ph.image ?? Image(systemName: "dot.radiowaves.left.and.right")).resizable().scaledToFill() }
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 64)).foregroundStyle(Nuru.gold.opacity(0.8))
            }
        }
        .frame(width: 240, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
    }

    private func statusPill(_ p: RadioProgram) -> some View {
        HStack(spacing: 6) {
            if p.isLive {
                Circle().fill(.white).frame(width: 6, height: 6)
                Text("LIVE ON AIR").font(.inter(10, .bold)).kerning(1.2)
            } else {
                Icon(.clock, size: 10, color: .white)
                Text("UP NEXT\(p.scheduledAt.map { " · " + radioDate($0) } ?? "")")
                    .font(.inter(10, .bold)).kerning(1.2)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(p.isLive ? Color(hex: 0xDC2626) : Color.white.opacity(0.14), in: Capsule())
    }

    private func playButton(_ p: RadioProgram) -> some View {
        Button { vm.togglePlay() } label: {
            Image(systemName: vm.playing ? "pause.fill" : "play.fill")
                .font(.system(size: 30)).foregroundStyle(Nuru.navy)
                .frame(width: 84, height: 84)
                .background(LinearGradient(colors: [Nuru.gold, Color(hex: 0xB6862F)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .shadow(color: Nuru.gold.opacity(0.5), radius: 20, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(p.streamUrl == nil)
        .opacity(p.streamUrl == nil ? 0.4 : 1)
    }

    private var reactions: some View {
        HStack(spacing: 14) {
            reactionChip("heart", "❤️", vm.counts?.heart)
            reactionChip("amen", "🙏", vm.counts?.amen)
            reactionChip("fire", "🔥", vm.counts?.fire)
        }
    }

    private func reactionChip(_ kind: String, _ emoji: String, _ count: Int?) -> some View {
        Button { Task { await vm.react(kind) } } label: {
            HStack(spacing: 5) {
                Text(emoji).font(.system(size: 16))
                if let c = count, c > 0 { Text("\(c)").font(.inter(12, .bold)).foregroundStyle(.white) }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var offAir: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 44)).foregroundStyle(Nuru.gold.opacity(0.7))
            Text("Off air right now").font(.fraunces(20, .semibold)).foregroundStyle(.white)
            Text("The Goodness Mission Radio will be back — check again soon.")
                .font(.inter(12)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center).padding(.horizontal, 48)
        }
    }
}

private func radioDate(_ iso: String) -> String {
    guard let d = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let f = DateFormatter(); f.dateFormat = "EEE h:mm a"
    return f.string(from: d)
}
