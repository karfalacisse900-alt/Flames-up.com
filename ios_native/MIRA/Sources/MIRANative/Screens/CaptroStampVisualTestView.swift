#if DEBUG
import SwiftUI

/// Non-writing visual QA. Example data is intentionally confined to DEBUG;
/// the same production card is shown on a real Captro feed photograph.
public struct CaptroStampVisualTestView: View {
  @State private var index = 0
  @State private var opened = false
  @State private var photoLoaded = false
  public init() {}

  private let kinds: [CaptroEditorialCardType] = CaptroEditorialCardType.allCases
  private let photoURL = "https://imagedelivery.net/DY-IgVdOm-0zb0K5ZFnpKA/81cd6cb6-ec4c-4a22-e356-3ecd1613cd00/public"
  private var kind: CaptroEditorialCardType { kinds[index] }
  private var content: CaptroEditorialCardContent {
    switch kind {
    case .place:
      return CaptroEditorialCardContent(type: .place, title: "Ruffian", subtitle: "East Village",
        chipText: "469 Saves", description: "Cute wine bar with awesome food options. Perfect for girls night and first date.",
        username: "@atlanta_gao")
    case .club:
      return CaptroEditorialCardContent(type: .club, title: "NYC Photo Club", subtitle: "Manhattan",
        chipText: "127 Members", description: "Weekly photo walks and casual meetups for city photographers.",
        username: "@karfala")
    case .event:
      return CaptroEditorialCardContent(type: .event, title: "Bronx Run Club", subtitle: "Bronx",
        chipText: "Sep 28", supportingText: "8:00 PM · $5 entry", username: "@bronxrunclub")
    case .meetup:
      return CaptroEditorialCardContent(type: .meetup, title: "Coffee Walk", subtitle: "Soho",
        chipText: "12 Going", supportingText: "Sunday · 11 AM", username: "@maya")
    case .deal:
      return CaptroEditorialCardContent(type: .deal, title: "Joe’s Pizza", subtitle: "Greenwich Village",
        chipText: "20% Off", supportingText: "Today until 8 PM", username: "@joespizza")
    }
  }

  public var body: some View {
    VStack(spacing: 0) {
      feedHeader
      GeometryReader { proxy in
        ZStack(alignment: .bottomLeading) {
          MIRACachedImage(url: photoURL, maxPixelSize: 1200, animatesNetworkLoad: false,
            onImageLoaded: { _ in photoLoaded = true }) { image in
              image.resizable().scaledToFill()
          } placeholder: {
            Color(red: 0.82, green: 0.84, blue: 0.80)
              .overlay { ProgressView().tint(.black) }
          }
          .frame(width: proxy.size.width, height: proxy.size.height)
          .clipped()

          CaptroEditorialOverlayCard(content: content, onOpen: { opened = true })
            .frame(width: CaptroEditorialCardLayout.width(for: proxy.size.width), alignment: .leading)
            .padding(CaptroEditorialCardLayout.inset)
        }
      }
      .aspectRatio(4.0 / 5.0, contentMode: .fit)

      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 22) {
          Image(systemName: "heart"); Image(systemName: "bubble.right"); Image(systemName: "paperplane")
          Spacer(); Image(systemName: "bookmark")
        }.font(.system(size: 21, weight: .regular))
        Text("A real-feed-size editorial check for \(kind.rawValue).")
          .font(.system(size: 14.5)).lineLimit(2)
        Button("Next family") { index = (index + 1) % kinds.count }
          .font(.system(size: 15, weight: .semibold))
          .accessibilityIdentifier("stamp.next")
      }
      .padding(.horizontal, 14).padding(.vertical, 12)
      Spacer(minLength: 0)
    }
    .background(Color.white)
    .overlay(alignment: .topLeading) {
      if photoLoaded {
        Color.clear.frame(width: 1, height: 1)
          .accessibilityElement()
          .accessibilityIdentifier("stamp.photo.loaded")
      }
    }
    .sheet(isPresented: $opened) {
      VStack { Text(content.accessibilityLabel); Button("Close") { opened = false } }.padding()
    }
  }

  private var feedHeader: some View {
    HStack(spacing: 10) {
      Circle().fill(Color.black).frame(width: 38, height: 38)
        .overlay { Text("C").font(.headline).foregroundStyle(.white) }
      VStack(alignment: .leading, spacing: 1) {
        Text("Captro").font(.system(size: 15, weight: .semibold))
        Text("New York").font(.system(size: 12)).foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
    }
    .padding(.horizontal, 14).frame(height: 58)
  }

}
#endif
