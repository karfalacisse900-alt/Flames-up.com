import AVFoundation
import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// Native document capture with server-side receipt/invoice recognition. The user never selects
/// a document type. Sensitive bytes remain in memory and are sent only after Verify is tapped.
private enum AuraScanMode: String, CaseIterable, Identifiable {
  case receipt = "Receipt"
  case qr = "QR"

  var id: String { rawValue }
}

public struct AuraScanView: View {
  @Environment(\.openURL) private var openURL
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
  @State private var mode: AuraScanMode = .receipt
  @State private var didAttemptAutomaticReceiptScan = false
  @State private var showingVerificationResult = false
  @State private var qrStatusMessage: String?
  @State private var lastRecognizedAuraURL: URL?

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
    ZStack {
      Color.black.ignoresSafeArea()

      if mode == .qr {
        qrScannerSurface
      } else if let selectedDocument {
        documentPreview(selectedDocument)
      } else {
        cameraPreviewStage
      }

      scanChrome
    }
    .fullScreenCover(isPresented: $showingScanner) {
      AuraDocumentScannerView { result in
        showingScanner = false
        handleScannedPages(result)
      } cancellation: {
        showingScanner = false
      }
      .ignoresSafeArea()
    }
    .sheet(isPresented: $showingVerificationResult) {
      verificationResultSheet
        .presentationDetents([.fraction(0.52), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(MIRATheme.Color.paperCanvas)
    }
    .fileImporter(
      isPresented: $showingImporter,
      allowedContentTypes: [.pdf, .image],
      allowsMultipleSelection: false,
      onCompletion: handleImportedURLs
    )
    .onAppear { attemptAutomaticReceiptScanIfSafe() }
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      resetResult()
      Task { await loadPhoto(item) }
    }
    .onChange(of: mode) { _, newMode in
      clearSelection()
      qrStatusMessage = nil
      lastRecognizedAuraURL = nil
      if newMode == .receipt {
        attemptAutomaticReceiptScanIfSafe()
      }
    }
    .alert(
      "Scan",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK") { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "Aura could not complete that scan.")
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background {
        clearSelection()
        showingScanner = false
      } else if phase == .active {
        attemptAutomaticReceiptScanIfSafe()
      }
    }
  }

  private var cameraPreviewStage: some View {
    ZStack {
      Color.black

      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.white.opacity(0.56), lineWidth: 1.25)
        .padding(.horizontal, 34)
        .padding(.top, 94)
        .padding(.bottom, 174)

      Image(systemName: "viewfinder")
        .font(.system(size: 244, weight: .ultraLight))
        .foregroundStyle(Color.white.opacity(0.72))

      VStack(spacing: 9) {
        Image(systemName: "doc.viewfinder")
          .font(.title)
        Text("Receipt or invoice")
          .font(.headline)
        Text("Tap the shutter to open the document camera")
          .font(.footnote)
          .foregroundStyle(Color.white.opacity(0.68))
      }
      .foregroundStyle(Color.white)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 54)
    }
    .ignoresSafeArea()
  }

  @ViewBuilder
  private var qrScannerSurface: some View {
    if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
      AuraQRDataScannerView(
        onPayload: handleQRPayload,
        onUnavailable: { message in qrStatusMessage = message }
      )
      .ignoresSafeArea()
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(Color.white.opacity(0.82), lineWidth: 2)
          .frame(width: 246, height: 246)
          .allowsHitTesting(false)
      }
    } else {
      VStack(spacing: 12) {
        Image(systemName: "qrcode.viewfinder")
          .font(.system(size: 54, weight: .light))
        Text("QR scanning unavailable")
          .font(.headline)
        Text(qrUnavailableMessage)
          .font(.footnote)
          .foregroundStyle(Color.white.opacity(0.68))
          .multilineTextAlignment(.center)
      }
      .foregroundStyle(Color.white)
      .padding(.horizontal, 36)
    }
  }

  private var scanChrome: some View {
    VStack(spacing: 0) {
      Picker("Scan mode", selection: $mode) {
        ForEach(AuraScanMode.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .controlSize(.mini)
      .frame(width: 154)
      .accessibilityLabel("Scan mode")

      Spacer()

      if mode == .receipt {
        if let selectedDocument {
          documentActionTray(selectedDocument)
        } else {
          receiptCaptureControls
        }
      } else {
        qrStatusTray
      }
    }
    .safeAreaPadding(.top, 8)
    .padding(.horizontal, 18)
    .padding(.bottom, 88)
  }

  private var receiptCaptureControls: some View {
    HStack(alignment: .center, spacing: 28) {
      PhotosPicker(selection: $selectedPhoto, matching: .images) {
        scanActionLabel("Photos", systemImage: "photo.on.rectangle")
      }
      .buttonStyle(.plain)

      Button {
        beginScan()
      } label: {
        ZStack {
          Circle()
            .stroke(Color.white, lineWidth: 4)
            .frame(width: 72, height: 72)
          Circle()
            .fill(Color.white)
            .frame(width: 58, height: 58)
        }
        .accessibilityLabel("Scan Document")
      }
      .buttonStyle(.plain)

      Button {
        beginImport()
      } label: {
        scanActionLabel("Import", systemImage: "square.and.arrow.down")
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
  }

  private func scanActionLabel(_ title: String, systemImage: String) -> some View {
    VStack(spacing: 5) {
      Image(systemName: systemImage)
        .font(.system(size: 19, weight: .semibold))
        .frame(width: 46, height: 46)
        .background(Color.black.opacity(0.54), in: Circle())
      Text(title)
        .font(.caption2.weight(.semibold))
    }
    .foregroundStyle(Color.white)
    .frame(width: 64)
  }

  private func documentPreview(_ document: AuraLocalDocument) -> some View {
    ZStack {
      Color.black
      if let image = actualDocumentPreview(document) {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.horizontal, 12)
          .padding(.vertical, 76)
      } else {
        VStack(spacing: 12) {
          Image(systemName: "doc.richtext.fill")
            .font(.system(size: 64, weight: .regular))
          Text("Document preview unavailable")
            .font(.headline)
        }
        .foregroundStyle(Color.white)
      }
    }
    .ignoresSafeArea()
  }

  private func documentActionTray(_ document: AuraLocalDocument) -> some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(spacing: 10) {
        Image(systemName: verificationResult == nil ? "doc.viewfinder" : "checkmark.seal.fill")
          .foregroundStyle(verificationResult == nil ? MIRATheme.Color.auraViolet : MIRATheme.Color.forest)
        VStack(alignment: .leading, spacing: 2) {
          Text(verificationResult.map { detectedTypeTitle($0) } ?? "Ready to verify")
            .font(.headline)
          Text(document.filename)
            .font(.caption)
            .foregroundStyle(MIRATheme.Color.textSecondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
      }

      HStack(spacing: 10) {
        Button("Retake") { clearSelection() }
          .buttonStyle(.bordered)
          .tint(MIRATheme.Color.textPrimary)

        Button {
          if verificationResult == nil {
            verify(document)
          } else {
            showingVerificationResult = true
          }
        } label: {
          if isVerifying {
            ProgressView()
              .frame(maxWidth: .infinity)
          } else {
            Text(verificationResult == nil ? "Verify Document" : "View Result")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(MIRATheme.Color.auraViolet)
        .disabled(isVerifying)
      }
    }
    .padding(14)
    .foregroundStyle(MIRATheme.Color.textPrimary)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var qrStatusTray: some View {
    VStack(spacing: 5) {
      Label(
        qrStatusMessage ?? "Point the camera at an Aura QR code",
        systemImage: lastRecognizedAuraURL == nil ? "qrcode.viewfinder" : "checkmark.circle.fill"
      )
      .font(.footnote.weight(.semibold))
      .multilineTextAlignment(.center)

      if let lastRecognizedAuraURL {
        Text(lastRecognizedAuraURL.absoluteString)
          .font(.caption2.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .foregroundStyle(Color.white)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(Color.black.opacity(0.62), in: Capsule())
  }

  @ViewBuilder
  private var verificationResultSheet: some View {
    ScrollView {
      VStack(spacing: 14) {
        if let verificationResult {
          verificationTicket(verificationResult)
        } else {
          ProgressView("Checking document…")
            .frame(maxWidth: .infinity, minHeight: 180)
        }

        Button("Done") { showingVerificationResult = false }
          .buttonStyle(.bordered)
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 24)
    }
    .background(MIRATheme.Color.paperCanvas.ignoresSafeArea())
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
        showingVerificationResult = true
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

  private func attemptAutomaticReceiptScanIfSafe() {
    guard mode == .receipt,
          selectedDocument == nil,
          !didAttemptAutomaticReceiptScan,
          scenePhase == .active else { return }
    didAttemptAutomaticReceiptScan = true
    guard VNDocumentCameraViewController.isSupported,
          AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
    DispatchQueue.main.async {
      guard mode == .receipt, selectedDocument == nil else { return }
      showingScanner = true
    }
  }

  private var qrUnavailableMessage: String {
    if !DataScannerViewController.isSupported {
      return "Live QR scanning is not supported on this iPhone."
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .denied, .restricted:
      return "Camera access is unavailable. Allow camera access in Settings to scan QR codes."
    default:
      return "The camera is temporarily unavailable. Close another camera app and try again."
    }
  }

  private func handleQRPayload(_ payload: String) {
    guard let url = recognizedAuraURL(from: payload) else {
      lastRecognizedAuraURL = nil
      qrStatusMessage = "That QR code is not an Aura link."
      return
    }
    guard url != lastRecognizedAuraURL else { return }
    lastRecognizedAuraURL = url
    qrStatusMessage = "Aura link recognized."
    openURL(url) { accepted in
      guard !accepted else { return }
      Task { @MainActor in
        guard lastRecognizedAuraURL == url else { return }
        qrStatusMessage = "Aura link recognized, but no supported destination is available."
      }
    }
  }

  private func recognizedAuraURL(from payload: String) -> URL? {
    let clean = payload.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty,
          clean.utf8.count <= 2_048,
          clean.rangeOfCharacter(from: .controlCharacters) == nil,
          let components = URLComponents(string: clean),
          components.scheme?.lowercased() == "aura",
          components.user == nil,
          components.password == nil,
          !(components.host ?? "").isEmpty || !components.path.isEmpty,
          let url = components.url else {
      return nil
    }
    return url
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
    showingVerificationResult = false
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

}

private struct AuraQRDataScannerView: UIViewControllerRepresentable {
  let onPayload: (String) -> Void
  let onUnavailable: (String) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onPayload: onPayload, onUnavailable: onUnavailable)
  }

  func makeUIViewController(context: Context) -> DataScannerViewController {
    let scanner = DataScannerViewController(
      recognizedDataTypes: [.barcode(symbologies: [.qr])],
      qualityLevel: .balanced,
      recognizesMultipleItems: false,
      isHighFrameRateTrackingEnabled: false,
      isPinchToZoomEnabled: true,
      isGuidanceEnabled: false,
      isHighlightingEnabled: true
    )
    scanner.delegate = context.coordinator
    let coordinator = context.coordinator
    DispatchQueue.main.async {
      do {
        try scanner.startScanning()
      } catch {
        coordinator.reportUnavailable()
      }
    }
    return scanner
  }

  func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

  static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
    uiViewController.stopScanning()
  }

  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    private let onPayload: (String) -> Void
    private let onUnavailable: (String) -> Void
    private var lastPayload: String?
    private var lastPayloadDate = Date.distantPast

    init(onPayload: @escaping (String) -> Void, onUnavailable: @escaping (String) -> Void) {
      self.onPayload = onPayload
      self.onUnavailable = onUnavailable
    }

    func dataScanner(
      _ dataScanner: DataScannerViewController,
      didAdd addedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      for item in addedItems {
        guard case .barcode(let barcode) = item,
              let payload = barcode.payloadStringValue else { continue }
        let now = Date()
        guard payload != lastPayload || now.timeIntervalSince(lastPayloadDate) > 1.5 else { continue }
        lastPayload = payload
        lastPayloadDate = now
        onPayload(payload)
        break
      }
    }

    func dataScanner(
      _ dataScanner: DataScannerViewController,
      becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
    ) {
      reportUnavailable()
    }

    func reportUnavailable() {
      onUnavailable("Live QR scanning became unavailable. Close another camera app and try again.")
    }
  }
}
