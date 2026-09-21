#if DEBUG
import SwiftUI

/// Non-writing visual QA. The photo is a read-only public Captro feed image;
/// the stamp is the production component at its real responsive feed size.
public struct CaptroStampVisualTestView: View {
  @State private var index = 0
  @State private var opened = false
  @State private var photoLoaded = false
  public init() {}

  private let kinds: [CaptroStampKind] = [.social, .club, .event, .meetup, .deal]
  private let photoURL = "https://imagedelivery.net/DY-IgVdOm-0zb0K5ZFnpKA/81cd6cb6-ec4c-4a22-e356-3ecd1613cd00/public"
  private var kind: CaptroStampKind { kinds[index] }
  private var content: CaptroStampContent {
    switch kind {
    case .social:
      return fixture(title: "NYC Ferry", metadata: nil, terms: nil)
    case .club:
      return fixture(title: "Yoga NYC", metadata: nil, terms: "Free to join")
    case .event:
      return fixture(title: "Bronx Run Club", metadata: nil, terms: "4:49 PM · $5", month: "SEP", day: "04")
    case .meetup:
      return fixture(title: "Photo Walk", metadata: "DUMBO", terms: "SAT · 2 PM · 8 GOING")
    default:
      return fixture(title: "$4 Back", metadata: "Joe’s Pizza", terms: "Spend $20+")
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

          CaptroPostStamp(content: content, onOpen: { opened = true }, compact: true)
            .frame(width: CaptroStampLayout.feedWidth(for: proxy.size.width), alignment: .leading)
            .padding(CaptroStampLayout.feedInset)
        }
      }
      .aspectRatio(4.0 / 5.0, contentMode: .fit)

      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 22) {
          Image(systemName: "heart"); Image(systemName: "bubble.right"); Image(systemName: "paperplane")
          Spacer(); Image(systemName: "bookmark")
        }.font(.system(size: 21, weight: .regular))
        Text("A real-feed-size material check for \(kind.displayName.lowercased()).")
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
      VStack { Text(content.accessibleStampLabel); Button("Close") { opened = false } }.padding()
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

  private func fixture(title: String, metadata: String?, terms: String?, month: String? = nil, day: String? = nil) -> CaptroStampContent {
    CaptroStampContent(kind: kind, title: title, metadata: metadata,
      description: "Visual QA fixture", footer: "@captro · Sep 20", actionTitle: nil, contributors: [],
      variant: kind.stampVariants[0], terms: terms, postID: "test-post",
      attachmentID: kind == .social ? nil : "test-attachment", dateMonth: month, dateDay: day)
  }
}
#endif
