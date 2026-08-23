import SwiftUI

public enum AuraScanDocumentKind: String, CaseIterable, Identifiable {
  case receipt
  case invoice

  public var id: String { rawValue }

  var label: String {
    switch self {
    case .receipt: return "Scan Receipt"
    case .invoice: return "Scan Invoice"
    }
  }

  var systemImage: String {
    switch self {
    case .receipt: return "camera.fill"
    case .invoice: return "doc.text.viewfinder"
    }
  }
}

/// Aura Mobile's Scan tab. Capture is intentionally not wired to the legacy Captro camera
/// (`MIRAStoryLiveCameraView`) yet: that view is built around short-form story video/photo
/// capture, not full-document capture, and needs a real edge-detection review before reuse.
/// This screen is the entry point and honest not-yet-connected state for the capture flow.
public struct AuraScanView: View {
  let api: MIRAAPIClient
  @State private var pendingDocumentKind: AuraScanDocumentKind?

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: MIRATheme.Space.lg) {
        HStack(spacing: MIRATheme.Space.sm) {
          ForEach(AuraScanDocumentKind.allCases) { kind in
            Button {
              pendingDocumentKind = kind
            } label: {
              VStack(spacing: MIRATheme.Space.xs) {
                Image(systemName: kind.systemImage)
                  .font(.system(size: 22, weight: .semibold))
                Text(kind.label)
                  .font(.system(size: 13, weight: .semibold))
                  .multilineTextAlignment(.center)
              }
              .foregroundStyle(MIRATheme.Color.textPrimary)
              .frame(maxWidth: .infinity, minHeight: 84)
            }
            .miraCardSurface()
          }

          Button {
          } label: {
            VStack(spacing: MIRATheme.Space.xs) {
              Image(systemName: "square.and.arrow.up")
                .font(.system(size: 22, weight: .semibold))
              Text("Import PDF/Image")
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            }
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 84)
          }
          .miraCardSurface()
        }

        if let pendingDocumentKind {
          MIRAEmptyState(
            title: "Camera capture not wired up yet",
            message: "\(pendingDocumentKind.label) needs a document-capture camera flow and a connection to a verification provider before it can produce a real result.",
            systemImage: "camera.metering.unknown"
          )
          .miraCardSurface()
        } else {
          MIRAEmptyState(
            title: "Choose a document type",
            message: "Aura sends the selected type with the provider request. No document is verified until it is captured and submitted.",
            systemImage: "doc.viewfinder"
          )
          .miraCardSurface()
        }

        Spacer()
      }
      .padding(MIRATheme.Space.lg)
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Scan")
    }
  }
}
