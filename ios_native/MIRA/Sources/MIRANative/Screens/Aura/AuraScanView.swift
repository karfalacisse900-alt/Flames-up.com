import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

public enum AuraScanDocumentKind: String, CaseIterable, Equatable, Identifiable, Sendable {
  case receipt
  case invoice

  public var id: String { rawValue }

  var title: String {
    switch self {
    case .receipt: return "Receipt"
    case .invoice: return "Invoice"
    }
  }

  var scanLabel: String { "Scan \(title)" }
}

/// Native receipt/invoice capture and bounded local import. Selected bytes remain only in memory
/// and are sent only after the user taps Verify. Veryfi parsing and screening are kept distinct
/// from independent purchase confirmation, Aura proof issuance, and blockchain submission.
public struct AuraScanView: View {
  @Environment(\.scenePhase) private var scenePhase
  let api: MIRAAPIClient
  @ObservedObject private var wallet: AuraWalletStore
  @ObservedObject private var proofs: AuraProofLifecycleStore
  @StateObject private var gateway: AuraWalletGatewayStore
  @State private var selectedDocument: AuraLocalDocument?
  @State private var pendingKind: AuraScanDocumentKind = .receipt
  @State private var showingScanner = false
  @State private var showingImporter = false
  @State private var errorMessage: String?
  @State private var verificationResult: AuraDocumentVerificationResult?
  @State private var proofSubmission: AuraPurchaseProofSubmission?
  @State private var isVerifying = false

  public init(
    api: MIRAAPIClient,
    wallet: AuraWalletStore,
    proofs: AuraProofLifecycleStore
  ) {
    self.api = api
    self.wallet = wallet
    self.proofs = proofs
    _gateway = StateObject(wrappedValue: AuraWalletGatewayStore(api: api))
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: MIRATheme.Space.lg) {
          actionGrid
          if let selectedDocument {
            selectedDocumentCard(selectedDocument)
            if let verificationResult {
              verificationResultCard(verificationResult)
            }
          } else {
            MIRAEmptyState(
              title: "Scan or import a document",
              message: "Choose a receipt or invoice. Aura keeps the selected bytes only in memory and clears them when you clear the selection or leave the app.",
              systemImage: "doc.viewfinder"
            )
            .miraCardSurface()
          }
        }
        .padding(MIRATheme.Space.lg)
      }
      .background(MIRATheme.Color.appBackground.ignoresSafeArea())
      .navigationTitle("Scan")
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
      .alert(
        "Document error",
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
        // System camera/photo pickers may briefly move the app through `.inactive`. Keep the
        // in-memory selection for that transition, but clear it once Aura is truly backgrounded.
        if phase == .background {
          selectedDocument = nil
          verificationResult = nil
          proofSubmission = nil
        }
      }
    }
  }

  private var actionGrid: some View {
    VStack(spacing: MIRATheme.Space.sm) {
      HStack(spacing: MIRATheme.Space.sm) {
        scanButton(kind: .receipt, systemImage: "camera.viewfinder")
        scanButton(kind: .invoice, systemImage: "doc.text.viewfinder")
      }

      HStack(spacing: MIRATheme.Space.sm) {
        photoButton(kind: .receipt)
        photoButton(kind: .invoice)
      }

      Menu {
        Button("Import Receipt") { beginImport(.receipt) }
        Button("Import Invoice") { beginImport(.invoice) }
      } label: {
        Label("Import PDF or Image", systemImage: "square.and.arrow.down")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
          .frame(maxWidth: .infinity, minHeight: 52)
      }
      .miraCardSurface(cornerRadius: MIRATheme.Radius.medium)
    }
  }

  private func photoButton(kind: AuraScanDocumentKind) -> some View {
    PhotosPicker(
      selection: Binding<PhotosPickerItem?>(
        get: { nil },
        set: { item in
          guard let item else { return }
          pendingKind = kind
          selectedDocument = nil
          verificationResult = nil
          proofSubmission = nil
          Task { await loadPhoto(item, kind: kind) }
        }
      ),
      matching: .images
    ) {
      Label("\(kind.title) Photo", systemImage: "photo.on.rectangle")
        .font(.system(size: 13.5, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 48)
    }
    .miraCardSurface(cornerRadius: MIRATheme.Radius.medium)
  }

  private func scanButton(kind: AuraScanDocumentKind, systemImage: String) -> some View {
    Button {
      beginScan(kind)
    } label: {
      VStack(spacing: MIRATheme.Space.xs) {
        Image(systemName: systemImage)
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest)
        Text(kind.scanLabel)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(MIRATheme.Color.textPrimary)
      }
      .frame(maxWidth: .infinity, minHeight: 88)
    }
    .miraCardSurface(cornerRadius: MIRATheme.Radius.medium)
  }

  private func selectedDocumentCard(_ document: AuraLocalDocument) -> some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      if let image = document.firstPageImage {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: 320)
          .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous))
      } else {
        VStack(spacing: MIRATheme.Space.sm) {
          Image(systemName: "doc.richtext.fill")
            .font(.system(size: 52, weight: .regular))
            .foregroundStyle(MIRATheme.Color.forest)
          Text("PDF selected")
            .font(.system(size: 15, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous))
      }

      HStack {
        Label("\(document.kind.title) selected", systemImage: "checkmark.circle.fill")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(MIRATheme.Color.forest)
        Spacer()
        Text(document.source.rawValue)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.textMuted)
      }

      documentRow(label: "Filename", value: document.filename)
      documentRow(label: "Type", value: document.mediaType)
      documentRow(label: "Pages", value: String(document.pages.count))
      documentRow(label: "Size", value: Self.byteFormatter.string(fromByteCount: Int64(document.byteCount)))
      documentRow(label: "Local SHA-256", value: document.sha256Hex)

      VStack(alignment: .leading, spacing: MIRATheme.Space.xs) {
        Label(
          selectedDocumentStatus,
          systemImage: verificationResult?.documentVerified == true ? "checkmark.shield.fill" : "shield.lefthalf.filled"
        )
          .font(.system(size: 14, weight: .bold))
        Text(selectedDocumentStatusMessage(for: document))
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }
      .padding(MIRATheme.Space.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous))

      Button(isVerifying ? "Verifying…" : "Verify \(document.kind.title)") {
        verify(document)
      }
      .buttonStyle(AuraPrimaryButtonStyle())
      .disabled(isVerifying || (document.kind == .receipt && wallet.state != .unlocked))

      if document.kind == .receipt, wallet.state != .unlocked {
        Text("Unlock the local Aura wallet first. A Proof of Purchase must be authorized on this iPhone before it can enter the real Devnet mempool.")
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }

      Button("Clear Local Selection") {
        selectedDocument = nil
        verificationResult = nil
        proofSubmission = nil
      }
      .font(.system(size: 14, weight: .bold))
      .foregroundStyle(MIRATheme.Color.forest)
      .frame(maxWidth: .infinity, minHeight: 44)
    }
    .padding(MIRATheme.Space.lg)
    .miraCardSurface()
  }

  private func verificationResultCard(_ result: AuraDocumentVerificationResult) -> some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      HStack {
        Label(
          result.submittedType == "receipt"
            ? (result.documentVerified ? "RECEIPT VERIFIED" : "RECEIPT COULD NOT BE VERIFIED")
            : result.verificationLabel,
          systemImage: result.documentVerified ? "checkmark.shield.fill" : "xmark.shield.fill"
        )
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(result.documentVerified ? MIRATheme.Color.forest : .red)
        Spacer()
      }

      if let merchant = result.merchant.name { documentRow(label: "Merchant / issuer", value: merchant) }
      if let date = result.date { documentRow(label: "Date", value: date) }
      if let total = result.total {
        documentRow(label: "Total", value: [result.currency, total].compactMap { $0 }.joined(separator: " "))
      }

      if result.submittedType == "receipt" {
        Text(result.documentVerified
          ? "Aura's document-verification checks passed. This does not claim merchant or payment confirmation."
          : "We couldn't verify this receipt.")
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)

        if !result.documentVerified, let selectedDocument {
          Button("Try Again") { verify(selectedDocument) }
            .buttonStyle(AuraSecondaryButtonStyle())
            .disabled(isVerifying)
        }
      }

      if let submission = proofSubmission,
         let record = proofs.records.first(where: { $0.proofId == submission.proofId }) {
        VStack(alignment: .leading, spacing: MIRATheme.Space.xs) {
          Label(proofStateLabel(record), systemImage: proofStateIcon(record))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(record.isConfirmed ? MIRATheme.Color.forest : MIRATheme.Color.textPrimary)
          documentRow(label: "Proof ID", value: record.proofId)
          documentRow(label: "Proof transaction", value: record.proofTransactionId)
          if let height = record.blockHeight {
            documentRow(label: "Included in block", value: height)
          }
          documentRow(
            label: "Confirmations",
            value: "\(record.confirmations) / \(record.requiredConfirmations)"
          )
          Text(record.isConfirmed
            ? "This canonical proof can now be checked for one feedback and Devnet contribution-reward action."
            : "The proof is in the real Aura transaction lifecycle. Confirmation status is read from the validated Devnet node.")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(MIRATheme.Color.textSecondary)
        }
        .padding(MIRATheme.Space.md)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: MIRATheme.Radius.medium, style: .continuous))
      } else if result.submittedType == "receipt" {
        Text(result.purchaseProof == nil
          ? "No blockchain proof was authorized. Provider parsing alone cannot create reputation standing or AUR."
          : "The provider authorized a privacy-safe proof, but it has not reached the Aura node.")
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      } else {
        Text("Invoice issued is not invoice paid. No Proof of Purchase or reward is created without independent payment confirmation.")
          .font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(MIRATheme.Color.textSecondary)
      }

      Text(result.privacy.providerAutoDeleteRequested
        ? "Aura does not retain the document; provider auto-delete was requested."
        : "Provider retention status unavailable.")
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textMuted)
    }
    .padding(MIRATheme.Space.lg)
    .miraCardSurface()
  }

  private func verify(_ document: AuraLocalDocument) {
    let identity = wallet.identity
    if document.kind == .receipt, identity == nil {
      errorMessage = "Unlock the local Aura wallet before verifying a receipt for blockchain submission."
      return
    }
    isVerifying = true
    verificationResult = nil
    proofSubmission = nil
    Task {
      defer { isVerifying = false }
      do {
        let result = try await api.verifyAuraDocument(
          document,
          ownerPublicKeyHex: identity?.publicKeyHex ?? ""
        )
        verificationResult = result
        guard document.kind == .receipt,
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
          submittedAtSeconds: submittedAt
        )
        proofSubmission = submission
        await proofs.refreshAll()
      } catch {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      }
    }
  }

  private func proofStateLabel(_ record: AuraPrivateProofRecord) -> String {
    switch record.state {
    case "confirmed": return "Confirmed on Aura Devnet"
    case "included": return "Included in block #\(record.blockHeight ?? "Unavailable")"
    case "pending": return "Pending in Aura mempool"
    default: return "Aura proof status unavailable"
    }
  }

  private var selectedDocumentStatus: String {
    guard let verificationResult else { return "Ready for provider verification" }
    guard verificationResult.submittedType == "receipt" else {
      return verificationResult.verificationLabel
    }
    return verificationResult.documentVerified
      ? "RECEIPT VERIFIED"
      : "RECEIPT COULD NOT BE VERIFIED"
  }

  private func selectedDocumentStatusMessage(for document: AuraLocalDocument) -> String {
    guard let verificationResult else {
      return "The format was accepted locally. Tap Verify to send this document through Aura's authenticated service to Veryfi."
    }
    guard document.kind == .receipt else {
      return "Provider analysis finished. An invoice is not proof of payment."
    }
    return verificationResult.documentVerified
      ? "Aura's document-verification checks passed. Proof submission continues through the real Devnet transaction lifecycle."
      : "We couldn't verify this receipt."
  }

  private func proofStateIcon(_ record: AuraPrivateProofRecord) -> String {
    switch record.state {
    case "confirmed": return "checkmark.seal.fill"
    case "included": return "cube.fill"
    default: return "clock.arrow.circlepath"
    }
  }

  private func documentRow(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.xxs) {
      Text(label)
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
      Text(value)
        .font(.system(size: 12.5, weight: .medium, design: label == "Local SHA-256" ? .monospaced : .default))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .textSelection(.enabled)
    }
  }

  private func beginScan(_ kind: AuraScanDocumentKind) {
    guard VNDocumentCameraViewController.isSupported else {
      errorMessage = "Document scanning is unavailable on this device. Import a PDF or image instead."
      return
    }
    pendingKind = kind
    selectedDocument = nil
    verificationResult = nil
    proofSubmission = nil
    showingScanner = true
  }

  private func beginImport(_ kind: AuraScanDocumentKind) {
    pendingKind = kind
    selectedDocument = nil
    verificationResult = nil
    proofSubmission = nil
    showingImporter = true
  }

  private func handleScannedPages(_ result: Result<[Data], Error>) {
    do {
      selectedDocument = try AuraLocalDocument.scanned(
        kind: pendingKind,
        pages: result.get()
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func handleImportedURLs(_ result: Result<[URL], Error>) {
    do {
      guard let url = try result.get().first else { return }
      selectedDocument = try AuraLocalDocument.imported(kind: pendingKind, url: url)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func loadPhoto(_ item: PhotosPickerItem, kind: AuraScanDocumentKind) async {
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        throw AuraLocalDocumentError.inaccessible
      }
      selectedDocument = try AuraLocalDocument.photoImported(kind: kind, data: data)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private static let byteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB]
    formatter.countStyle = .file
    return formatter
  }()
}
