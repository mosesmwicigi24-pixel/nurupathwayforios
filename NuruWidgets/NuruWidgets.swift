// Nuru home-screen widgets — branded doors into the app's heart surfaces:
// Pathway (continue your journey), Chat (the family), Radio (tune in live).
// Static launchers by design: the free personal signing team has no App Group
// entitlement, so no live data crosses the boundary — each widget is a warm
// navy-and-gold door that deep-links via nuru:// straight to its surface
// (RootView routes the URL). SF Symbols + system serif here: the extension
// has its own bundle and doesn't carry the app's Fraunces/Inter/lucide files.
import WidgetKit
import SwiftUI

struct NuruEntry: TimelineEntry { let date: Date }

struct NuruStaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> NuruEntry { NuruEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (NuruEntry) -> Void) {
        completion(NuruEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NuruEntry>) -> Void) {
        completion(Timeline(entries: [NuruEntry(date: .now)], policy: .never))
    }
}

// Brand palette — mirrors NuruTheme's navy/gold.
private enum WBrand {
    static let navyTop  = Color(red: 0.078, green: 0.208, blue: 0.349)  // 0x143559
    static let navy     = Color(red: 0.043, green: 0.122, blue: 0.200)  // 0x0B1F33
    static let navyDeep = Color(red: 0.000, green: 0.075, blue: 0.184)  // 0x00132F
    static let gold     = Color(red: 0.784, green: 0.608, blue: 0.235)  // 0xC89B3C
    static let goldHi   = Color(red: 0.878, green: 0.722, blue: 0.369)  // 0xE0B85E
}

/// One door: gold-ringed icon, gold kicker, serif title, soft caption on the
/// ceremony-navy gradient.
private struct NuruDoor: View {
    let icon: String
    let kicker: String
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WBrand.goldHi)
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.09), in: Circle())
                    .overlay(Circle().stroke(WBrand.gold.opacity(0.45), lineWidth: 1))
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text(kicker)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.3)
                .foregroundStyle(WBrand.goldHi)
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.8)
                .padding(.top, 1)
            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [WBrand.navyTop, WBrand.navy, WBrand.navyDeep],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct NuruPathwayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NuruPathwayWidget", provider: NuruStaticProvider()) { _ in
            NuruDoor(icon: "book.fill", kicker: "PATHWAY",
                     title: "Continue your journey", caption: "Pick up today's module")
                .widgetURL(URL(string: "nuru://pathway"))
        }
        .configurationDisplayName("Pathway")
        .description("Jump straight into your discipleship pathway.")
        .supportedFamilies([.systemSmall])
    }
}

struct NuruChatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NuruChatWidget", provider: NuruStaticProvider()) { _ in
            NuruDoor(icon: "bubble.left.and.bubble.right.fill", kicker: "CHAT",
                     title: "The family is talking", caption: "Open your conversations")
                .widgetURL(URL(string: "nuru://chat"))
        }
        .configurationDisplayName("Chat")
        .description("Open your Nuru conversations in one tap.")
        .supportedFamilies([.systemSmall])
    }
}

struct NuruRadioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NuruRadioWidget", provider: NuruStaticProvider()) { _ in
            NuruDoor(icon: "dot.radiowaves.left.and.right", kicker: "NURU RADIO",
                     title: "Tune in live", caption: "Worship & the Word, on air")
                .widgetURL(URL(string: "nuru://radio"))
        }
        .configurationDisplayName("Nuru Radio")
        .description("Open the live radio player in one tap.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct NuruWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NuruPathwayWidget()
        NuruChatWidget()
        NuruRadioWidget()
    }
}
