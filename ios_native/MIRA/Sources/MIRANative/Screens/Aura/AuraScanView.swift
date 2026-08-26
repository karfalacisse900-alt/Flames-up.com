import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// Native document capture with server-side receipt/invoice recognition. The user never selects
/// a document type. Sensitive bytes remain in memory and are sent only after Verify is tapped.
public struct AuraScanView: View {
  @Environment(\.scenePhase) private var scenePhase
  let api: MIRAAPIClient
  @ObservedObject private var wallet: AuraWalletStore
  @ObservedObject private var gateway: AuraWalletGatewayStore
  @ObservedObject private var proofs: AuraProofLifecycleStore
  @State private var selectedDocument: AuraLocalDocument?
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var showingScanner = false
  @State private var showingImporter = false
  @State private var errorMessage: String?
  @State private var verificationResult: AuraDocumentVerificationResult?
  @State private var proofSubmission: AuraPurchaseProofSubmission?
  @State private var isVerifying = false

  public init(
    api: MIRAAPIClient,
    wallet: AuraWalletStore,
    gateway: AuraWalletGatewayStore,
    proofs: AuraProofLifecycleStore
  ) {
    self.api = api
    self.wallet = wallet
    self.gateway = gateway
    self.proofs = proofs
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 14) {
          if let selectedDocument {
            documentPreview(selectedDocument)
            if let verificationResult {
              verificationTicket(verificationResult)
            }
          } else {
            captureCard
            privacyNote
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
      }
      .background(MIRATheme.Color.paperCanvas.ignoresSafeArea())
      .navigationTitle("Scan")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(MIRATheme.Color.paperCanvas, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { errorMessage = privacyHelp } label: {
            Image(systemName: "questionmark.circle")
          }
          .accessibilityLabel("Document privacy help")
        }
      }
      .sheet(isPresented: $showingScanner) {
        AuraDocumentScannerView { result in
          showingScanner = false
          handleScannedPages(result)
        } cancellation: {
          showingScanner = false
        }
        .ignoresSafeArea()
      }
      .fileImporter(
        isPresented: $showingImporter,
        allowedContentTypes: [.pdf, .image],
        allowsMultipleSelection: false,
        onCompletion: handleImportedURLs
      )
      .onChange(of: selectedPhoto) { _, item in
        guard let item else { return }
        resetResult()
        Task { await loadPhoto(item) }
      }
      .alert(
        "Document",
        isPresented: Binding(
          get: { errorMessage != nil },
          set: { if !$0 { errorMessage = nil } }
        )
      ) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "Aura could not inspect that document.")
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .background {
          clearSelection()
        }
      }
    }
  }

  private var captureCard: some View {
    VStack(spacing: 14) {
      cameraPreviewStage

      VStack(spacing: 14) {
        Text("Scan a receipt or invoice")
          .font(.title2)
          .fontWeight(.black)
          .foregroundStyle(MIRATheme.Color.textPrimary)

        Text("Aura automatically recognizes receipts and invoices.")
          .font(.subheadline)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .multilineTextAlignment(.center)

        Button {
          beginScan()
        } label: {
          Label("Scan Document", systemImage: "camera.viewfinder")
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(AuraTactilePrimaryButtonStyle())

        HStack(spacing: 12) {
          PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label("Photos", systemImage: "photo.on.rectangle")
              .font(.subheadline)
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(AuraTactileSecondaryButtonStyle())

          Button {
            beginImport()
          } label: {
            Label("Import", systemImage: "square.and.arrow.down")
              .font(.subheadline)
              .fontWeight(.semibold)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(AuraTactileSecondaryButtonStyle())
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity)
      .physicalAuraCard(cornerRadius: 17)
    }
  }

  private var cameraPreviewStage: some View {
    ZStack {
      Color.black.opacity(0.88)

      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.white.opacity(0.76), lineWidth: 1.5)
        .padding(.horizontal, 40)
        .padding(.vertical, 42)

      Image(systemName: "viewfinder")
        .font(.system(size: 230, weight: .ultraLight))
        .foregroundStyle(Color.white.opacity(0.92))

      VStack(spacing: 10) {
        Image(systemName: "doc.viewfinder")
          .font(.system(size: 34, weight: .medium))
        Text("Position the document inside the frame")
          .font(.subheadline)
          .fontWeight(.semibold)
        Text("Camera opens when you tap Scan Document")
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.72))
      }
      .foregroundStyle(Color.white)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 56)

      VStack {
        HStack {
          Label("Automatic recognition", systemImage: "sparkle.magnifyingglass")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(MIRATheme.Color.paperSurface, in: Capsule())
          Spacer()
        }
        Spacer()
      }
      .padding(14)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 330)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(MIRATheme.Color.inkBorder, lineWidth: 1.5)
    }
    .shadow(color: MIRATheme.Color.hardShadow, radius: 0, x: 0, y: 5)
    .padding(.bottom, 5)
    .accessibilityElement(children: .combine)
  }

  private var privacyNote: some View {
    Label(
      "Your document stays private and is submitted only when you choose to verify.",
      systemImage: "lock.shield.fill"
    )
    .font(.footnote)
    .foregroundStyle(MIRATheme.Color.textSecondary)
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MIRATheme.Color.paperSurface)
    .physicalAuraCard(cornerRadius: 15)
  }

  private func documentPreview(_ document: AuraLocalDocument) -> some View {
    VStack(spacing: 14) {
      ZStack(alignment: .topLeading) {
        Color.black.opacity(0.88)

        if let image = actualDocumentPreview(document) {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 390)
            .padding(12)
        } else {
          VStack(spacing: 12) {
            Image(systemName: "doc.richtext.fill")
              .font(.system(size: 72, weight: .regular))
              .foregroundStyle(Color.white.opacity(0.88))
            Text("Document preview unavailable")
              .font(.headline)
              .foregroundStyle(Color.white)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        Label(
          verificationResult.map { detectedTypeTitle($0) } ?? "Ready to verify",
          systemImage: verificationResult == nil ? "doc.badge.ellipsis" : "doc.text.magnifyingglass"
        )
        .font(.caption)
        .fontWeight(.bold)
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(MIRATheme.Color.paperSurface, in: Capsule())
        .padding(14)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 390)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(MIRATheme.Color.inkBorder, lineWidth: 1.5)
      }
      .shadow(color: MIRATheme.Color.hardShadow, radius: 0, x: 0, y: 5)
      .padding(.bottom, 5)

      VStack(alignment: .leading, spacing: 12) {
        Text(document.filename)
          .font(.subheadline)
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineLimit(2)

        if verificationResult == nil {
          Button(isVerifying ? "Verifying…" : "Verify Document") {
            verify(document)
          }
          .buttonStyle(AuraTactilePrimaryButtonStyle())
          .frame(maxWidth: .infinity)
          .disabled(isVerifying)
        }

        Button("Choose Another Document") { clearSelection() }
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(MIRATheme.Color.auraViolet)
          .frame(maxWidth: .infinity, minHeight: 42)
          .buttonStyle(AuraTactileSecondaryButtonStyle())
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .physicalAuraCard(cornerRadius: 17)
    }
  }

  private func verificationTicket(_ result: AuraDocumentVerificationResult) -> some View {
    VStack(spacing: 14) {
      AuraDocumentTicketCard(
        merchant: result.merchant.name,
        documentType: result.submittedType == "other" ? "document" : result.submittedType,
        date: result.date,
        currency: result.currency,
        total: result.total,
        status: result.documentVerified ? "Verified" : "Could not be verified",
        statusSystemImage: result.documentVerified ? "checkmark.seal.fill" : "xmark.seal.fill",
        statusColor: result.documentVerified ? MIRATheme.Color.forest : .red,
        detail: nil
      )

      if !result.documentVerified {
        Button("Try Again") {
          if let selectedDocument { verify(selectedDocument) }
        }
        .buttonStyle(AuraTactilePrimaryButtonStyle())
        .disabled(isVerifying)
      }

      proofLifecycle(result)
    }
  }

  @ViewBuilder
  private func proofLifecycle(_ result: AuraDocumentVerificationResult) -> some View {
    if result.submittedType == "receipt" {
      if let submission = proofSubmission,
         let record = proofs.records.first(where: { $0.proofId == submission.proofId }) {
        VStack(alignment: .leading, spacing: 8) {
          Label(proofStateLabel(record), systemImage: proofStateIcon(record))
            .font(.headline)
            .foregroundStyle(record.isConfirmed ? MIRATheme.Color.forest : MIRATheme.Color.auraViolet)
          Text("Proof \(shortIdentifier(record.proofId))")
            .font(.caption)
            .foregroundStyle(MIRATheme.Color.textSecondary)
          Text(record.isConfirmed ? "Saved to your Aura account." : "Finishing securely…")
            .font(.subheadline)
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .physicalAuraCard(cornerRadius: 16)
      } else if result.documentVerified && wallet.identity == nil {
        Label(
          "Receipt verified. Unlock your wallet to create its Aura proof.",
          systemImage: "lock.shield"
        )
        .font(.footnote)
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
    } else if result.submittedType == "invoice" && result.documentVerified {
      Text("Invoice verified. Payment was not confirmed, so no purchase proof was created.")
        .font(.footnote)
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .padding(14)
        .background(MIRATheme.Color.surfaceSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
  }

  private func verify(_ document: AuraLocalDocument) {
    isVerifying = true
    verificationResult = nil
    proofSubmission = nil
    Task {
      defer { isVerifying = false }
      do {
        let identity = wallet.identity
        let result = try await api.verifyAuraDocument(
          document,
          ownerPublicKeyHex: identity?.publicKeyHex ?? ""
        )
        verificationResult = result
        guard result.submittedType == "receipt",
              let identity,
              let attestation = result.purchaseProof else { return }
        let submission = try await gateway.submitPurchaseProof(
          attestation,
          from: wallet,
          identity: identity
        )
        let submittedAt = UInt64(attestation.timestampSeconds)
          ?? UInt64(max(0, Date().timeIntervalSince1970))
        proofs.record(
          submission: submission,
          owner: identity.address,
          submittedAtSeconds: submittedAt,
          documentType: result.submittedType,
          merchantName: result.merchant.name,
          documentDate: result.date,
          currency: result.currency,
          total: result.total
        )
        proofSubmission = submission
        await proofs.refreshAll()
      } catch {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      }
    }
  }

  private func detectedTypeTitle(_ result: AuraDocumentVerificationResult) -> String {
    switch result.submittedType {
    case "receipt": return "Receipt detected"
    case "invoice": return "Invoice detected"
    default: return "Document type unsupported"
    }
  }

  private func proofStateLabel(_ record: AuraPrivateProofRecord) -> String {
    switch record.state {
    case "confirmed": return "Aura proof ready"
    case "included", "pending": return "Creating Aura proof"
    default: return "Proof unavailable"
    }
  }

  private func proofStateIcon(_ record: AuraPrivateProofRecord) -> String {
    switch record.state {
    case "confirmed": return "checkmark.seal.fill"
    case "included": return "cube.fill"
    default: return "clock.arrow.circlepath"
    }
  }

  private func shortIdentifier(_ value: String) -> String {
    guard value.count > 14 else { return value }
    return "\(value.prefix(8))…\(value.suffix(6))"
  }

  private func actualDocumentPreview(_ document: AuraLocalDocument) -> UIImage? {
    if let image = document.firstPageImage {
      return image
    }
    guard document.mediaType == "application/pdf",
          let data = document.pages.first,
          let page = PDFDocument(data: data)?.page(at: 0) else {
      return nil
    }
    return page.thumbnail(of: CGSize(width: 900, height: 1_200), for: .mediaBox)
  }

  private func beginScan() {
    guard VNDocumentCameraViewController.isSupported else {
      errorMessage = "Document scanning is unavailable on this device. Import a PDF or image instead."
      return
    }
    resetResult()
    showingScanner = true
  }

  private func beginImport() {
    resetResult()
    showingImporter = true
  }

  private func resetResult() {
    selectedDocument = nil
    verificationResult = nil
    proofSubmission = nil
  }

  private func clearSelection() {
    resetResult()
    selectedPhoto = nil
  }

  private func handleScannedPages(_ result: Result<[Data], Error>) {
    do {
      selectedDocument = try AuraLocalDocument.scanned(pages: result.get())
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func handleImportedURLs(_ result: Result<[URL], Error>) {
    do {
      guard let url = try result.get().first else { return }
      selectedDocument = try AuraLocalDocument.imported(url: url)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func loadPhoto(_ item: PhotosPickerItem) async {
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        throw AuraLocalDocumentError.inaccessible
      }
      selectedDocument = try AuraLocalDocument.photoImported(data: data)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private var privacyHelp: String {
    "Aura uploads the selected document only after you tap Verify Document. The image is not shown publicly."
  }
}
