import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

public struct CaptroScanView: View {
  let api: MIRAAPIClient
  @StateObject private var purchase: CaptroScanPurchaseService

  @State private var selectedDocument: CaptroLocalDocument?
  @State private var detectedType: CaptroDetectedDocumentType?
  @State private var idempotencyKey: String?
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var result: CaptroScanVerificationResult?
  @State private var proof: CaptroScanProof?
  @State private var isDetecting = false
  @State private var isVerifying = false
  @State private var isPurchasing = false
  @State private var showingScanner = false
  @State private var showingImporter = false
  @State private var showingCreditPurchase = false
  @State private var showingDetails = false
  @State private var showingProof = false
  @State private var showingSavedConfirmation = false
  @State private var errorMessage: String?

  public init(api: MIRAAPIClient) {
    self.api = api
    _purchase = StateObject(wrappedValue: CaptroScanPurchaseService(api: api))
  }

  public var body: some View {
    NavigationStack {
      ZStack {
        CaptroScanPalette.background.ignoresSafeArea()
        ScrollView {
          VStack(spacing: 0) {
            scanHeader
            if let result {
              resultStage(result)
            } else if let document = selectedDocument {
              reviewStage(document)
            } else {
              captureStage
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, 20)
          .padding(.bottom, 40)
          .frame(maxWidth: .infinity)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
    }
    .task { await purchase.prepare() }
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      Task { await loadPhoto(item) }
    }
    .fullScreenCover(isPresented: $showingScanner) {
      CaptroDocumentScannerView(
        completion: { scanResult in
          handleScannedPages(scanResult)
          showingScanner = false
        },
        cancellation: { showingScanner = false }
      )
      .ignoresSafeArea()
    }
    .fileImporter(
      isPresented: $showingImporter,
      allowedContentTypes: [.pdf, .image],
      allowsMultipleSelection: false,
      onCompletion: handleImportedURLs
    )
    .sheet(isPresented: $showingCreditPurchase) {
      creditPurchaseSheet
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showingDetails) {
      if let result {
        detailsSheet(result)
      }
    }
    .sheet(isPresented: $showingProof) {
      if let proof {
        proofSheet(proof)
      }
    }
    .alert("Captro Scan", isPresented: errorBinding) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "Captro could not complete that request.")
    }
    .alert("Saved", isPresented: $showingSavedConfirmation) {
      Button("Done", role: .cancel) {}
    } message: {
      Text("This result is saved privately to your Captro account.")
    }
  }

  private var scanHeader: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Scan")
          .font(.system(size: 34, weight: .bold))
          .foregroundStyle(CaptroScanPalette.ink)
        Text("Receipt & invoice verification")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(CaptroScanPalette.secondaryInk)
      }
      Spacer()
      Image(systemName: "checkmark.seal")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(CaptroScanPalette.forest)
        .frame(width: 46, height: 46)
        .background(CaptroScanPalette.paper)
        .clipShape(Circle())
        .overlay(Circle().stroke(CaptroScanPalette.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
    .padding(.top, 18)
    .padding(.bottom, 24)
  }

  private var captureStage: some View {
    VStack(spacing: 24) {
      VStack(spacing: 8) {
        Text("Scan a receipt or invoice")
          .font(.system(size: 24, weight: .bold))
          .foregroundStyle(CaptroScanPalette.ink)
          .multilineTextAlignment(.center)
        Text("Captro automatically recognizes the document type.")
          .font(.system(size: 15, weight: .regular))
          .foregroundStyle(CaptroScanPalette.secondaryInk)
          .multilineTextAlignment(.center)
      }

      emptyPaperPreview

      VStack(spacing: 12) {
        Button(action: beginScan) {
          Label("Scan Document", systemImage: "doc.viewfinder")
            .captroPrimaryButtonLabel()
        }
        .buttonStyle(.miraPress)

        HStack(spacing: 12) {
          PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
            Label("Photos", systemImage: "photo.on.rectangle")
              .captroSecondaryButtonLabel()
          }
          .buttonStyle(.miraPress)

          Button(action: beginImport) {
            Label("Import", systemImage: "square.and.arrow.down")
              .captroSecondaryButtonLabel()
          }
          .buttonStyle(.miraPress)
        }
      }

      privacyCopy
    }
  }

  private var emptyPaperPreview: some View {
    ZStack {
      dottedEdge
      VStack(spacing: 18) {
        Image(systemName: "doc.text.viewfinder")
          .font(.system(size: 52, weight: .ultraLight))
          .foregroundStyle(CaptroScanPalette.forest)
        VStack(spacing: 9) {
          ForEach([CGFloat(0.82), 0.66, 0.9, 0.58], id: \.self) { width in
            Capsule()
              .fill(CaptroScanPalette.line)
              .frame(maxWidth: 190 * width)
              .frame(height: 5)
          }
        }
        Text("Capture or import for free")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(CaptroScanPalette.secondaryInk)
      }
      .frame(maxWidth: 310)
      .frame(height: 330)
      .background(CaptroScanPalette.paper)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(CaptroScanPalette.line, lineWidth: 1))
      .shadow(color: .black.opacity(0.11), radius: 20, x: 0, y: 12)
      .padding(.horizontal, 30)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 390)
  }

  private var dottedEdge: some View {
    HStack {
      VStack(spacing: 12) {
        ForEach(0..<8, id: \.self) { _ in
          Circle().fill(CaptroScanPalette.dot).frame(width: 6, height: 6)
        }
      }
      Spacer()
      VStack(spacing: 12) {
        ForEach(0..<8, id: \.self) { _ in
          Circle().fill(CaptroScanPalette.dot).frame(width: 6, height: 6)
        }
      }
    }
    .accessibilityHidden(true)
  }

  private var privacyCopy: some View {
    Label(
      "Your document stays private and uploads only after you approve verification.",
      systemImage: "lock.shield.fill"
    )
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(CaptroScanPalette.secondaryInk)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func reviewStage(_ document: CaptroLocalDocument) -> some View {
    VStack(spacing: 22) {
      documentPaper(document)

      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top, spacing: 12) {
          detectionStatus
          Spacer()
          Button {
            clearSelection()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(CaptroScanPalette.ink)
              .frame(width: 36, height: 36)
              .background(CaptroScanPalette.paper)
              .clipShape(Circle())
              .overlay(Circle().stroke(CaptroScanPalette.line, lineWidth: 1))
          }
          .buttonStyle(.miraPress)
          .accessibilityLabel("Choose another document")
        }

        if detectedType == .receipt || detectedType == .invoice {
          Divider().overlay(CaptroScanPalette.line)
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
              Text("Verification")
                .font(.system(size: 15, weight: .bold))
              Text("Charged only after you submit")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(CaptroScanPalette.secondaryInk)
            }
            Spacer()
            Text("$0.10")
              .font(.system(size: 25, weight: .bold, design: .rounded))
          }
          .foregroundStyle(CaptroScanPalette.ink)

          Button(action: beginVerification) {
            HStack(spacing: 9) {
              if isVerifying {
                ProgressView().tint(.white)
              } else {
                Image(systemName: "checkmark.shield.fill")
              }
              Text(isVerifying ? "Verifying…" : "Verify for $0.10")
            }
            .captroPrimaryButtonLabel()
          }
          .buttonStyle(.miraPress)
          .disabled(isVerifying || isDetecting)

          Text("A completed verification uses one $0.10 credit, including a legitimate Couldn't Verify result. Infrastructure failures are restored automatically.")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(CaptroScanPalette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        } else if detectedType == .unsupported {
          Divider().overlay(CaptroScanPalette.line)
          Text("Captro couldn't recognize this as a receipt or invoice. Choose a clearer image or import another document. You were not charged.")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(CaptroScanPalette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
          Button(action: clearSelection) {
            Label("Choose Another", systemImage: "arrow.counterclockwise")
              .captroSecondaryButtonLabel()
          }
          .buttonStyle(.miraPress)
        }
      }
      .padding(18)
      .background(CaptroScanPalette.paper.opacity(0.92))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(CaptroScanPalette.line, lineWidth: 1))
    }
  }

  private func documentPaper(_ document: CaptroLocalDocument) -> some View {
    ZStack {
      CaptroScanPalette.canvas
      if let image = document.firstPageImage {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .padding(14)
      } else {
        VStack(spacing: 12) {
          Image(systemName: "doc.richtext.fill")
            .font(.system(size: 54, weight: .regular))
          Text("Preview unavailable")
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(CaptroScanPalette.secondaryInk)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 430)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CaptroScanPalette.line, lineWidth: 1))
    .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
    .accessibilityLabel("Selected document preview")
  }

  private var detectionStatus: some View {
    HStack(alignment: .top, spacing: 11) {
      Group {
        if isDetecting {
          ProgressView().tint(CaptroScanPalette.forest)
        } else {
          Image(systemName: detectedType == .unsupported ? "questionmark.circle.fill" : "doc.text.magnifyingglass")
            .foregroundStyle(detectedType == .unsupported ? CaptroScanPalette.secondaryInk : CaptroScanPalette.forest)
        }
      }
      .frame(width: 24, height: 24)

      VStack(alignment: .leading, spacing: 3) {
        Text(isDetecting ? "Detecting document type…" : (detectedType?.title ?? "Ready to detect"))
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(CaptroScanPalette.ink)
        if let document = selectedDocument {
          Text("\(document.source.rawValue) · \(ByteCountFormatter.string(fromByteCount: Int64(document.byteCount), countStyle: .file))")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(CaptroScanPalette.secondaryInk)
        }
      }
    }
  }

  private func resultStage(_ result: CaptroScanVerificationResult) -> some View {
    VStack(spacing: 22) {
      VStack(spacing: 10) {
        Image(systemName: result.isVerified ? "checkmark.seal.fill" : "xmark.seal")
          .font(.system(size: 52, weight: .medium))
          .foregroundStyle(result.isVerified ? CaptroScanPalette.forest : CaptroScanPalette.secondaryInk)
        Text(result.isVerified ? "Verified" : "Couldn't Verify")
          .font(.system(size: 30, weight: .bold))
          .foregroundStyle(CaptroScanPalette.ink)
        if !result.isVerified {
          Text("Captro couldn't verify this document with the available information.")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(CaptroScanPalette.secondaryInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.top, 10)

      resultPaper(result)

      if result.isVerified {
        verifiedActions(result)
      } else {
        couldntVerifyActions
      }
    }
  }

  private func resultPaper(_ result: CaptroScanVerificationResult) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text(result.business?.name?.nonEmpty ?? documentTypeName(result.documentType))
          .font(.system(size: 23, weight: .bold, design: .serif))
          .foregroundStyle(CaptroScanPalette.ink)
        if let address = displayAddress(result.business?.address) {
          Text(address)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(CaptroScanPalette.secondaryInk)
        }
      }

      Divider().overlay(CaptroScanPalette.line)

      VStack(alignment: .leading, spacing: 9) {
        if let number = result.documentNumber?.nonEmpty {
          resultLine(label: result.documentType == "invoice" ? "Invoice" : "Receipt", value: "#\(number)")
        }
        if let date = result.issueDate?.nonEmpty {
          resultLine(
            label: result.documentType == "invoice" ? "Issued" : "Date",
            value: joinedDateTime(date, time: result.time) ?? date
          )
        }
        if result.documentType == "invoice", let due = result.dueDate?.nonEmpty {
          resultLine(label: "Due", value: due)
        }
        if let reference = result.transactionReference?.nonEmpty {
          resultLine(label: "Reference", value: reference)
        }
      }

      if let total = result.total?.nonEmpty {
        Divider().overlay(CaptroScanPalette.line)
        HStack(alignment: .firstTextBaseline) {
          Text("Total")
            .font(.system(size: 16, weight: .bold))
          Spacer()
          Text(money(total, currency: result.currency))
            .font(.system(size: 27, weight: .bold, design: .rounded))
        }
        .foregroundStyle(CaptroScanPalette.ink)
      }

      Text(result.billingState == "charged" ? "Verification fee paid · $0.10" : billingCopy(result.billingState))
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(CaptroScanPalette.secondaryInk)
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CaptroScanPalette.paper)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CaptroScanPalette.line, lineWidth: 1))
    .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 12)
  }

  private func resultLine(label: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Text(label.uppercased())
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(CaptroScanPalette.secondaryInk)
        .frame(width: 68, alignment: .leading)
      Text(value)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(CaptroScanPalette.ink)
        .textSelection(.enabled)
      Spacer(minLength: 0)
    }
  }

  private func verifiedActions(_ result: CaptroScanVerificationResult) -> some View {
    VStack(spacing: 12) {
      Button {
        showingDetails = true
      } label: {
        Label("View Details", systemImage: "list.bullet.rectangle")
          .captroPrimaryButtonLabel()
      }
      .buttonStyle(.miraPress)

      HStack(spacing: 12) {
        Button {
          showingSavedConfirmation = true
        } label: {
          Label("Save", systemImage: "bookmark.fill")
            .captroSecondaryButtonLabel()
        }
        .buttonStyle(.miraPress)

        if let proofID = result.proofId {
          Button {
            loadProof(proofID)
          } label: {
            Label("View Proof", systemImage: "checkmark.seal")
              .captroSecondaryButtonLabel()
          }
          .buttonStyle(.miraPress)
        }
      }

      Button("Scan Another", action: clearSelection)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(CaptroScanPalette.forest)
        .padding(.top, 4)
    }
  }

  private var couldntVerifyActions: some View {
    VStack(spacing: 12) {
      Button {
        result = nil
      } label: {
        Label("Try Again", systemImage: "arrow.counterclockwise")
          .captroPrimaryButtonLabel()
      }
      .buttonStyle(.miraPress)

      Button(action: clearSelection) {
        Label("Scan Another", systemImage: "doc.viewfinder")
          .captroSecondaryButtonLabel()
      }
      .buttonStyle(.miraPress)
    }
  }

  private var creditPurchaseSheet: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 20) {
        Image(systemName: "checkmark.shield.fill")
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(CaptroScanPalette.forest)

        VStack(alignment: .leading, spacing: 8) {
          Text("Add verification credits")
            .font(.system(size: 25, weight: .bold))
          Text("The App Store charges \(purchase.localizedPackPrice) for 10 Captro Scan credits. This verification uses one $0.10 credit.")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(CaptroScanPalette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }

        HStack {
          Text("10 verifications")
            .font(.system(size: 15, weight: .bold))
          Spacer()
          Text(purchase.localizedPackPrice)
            .font(.system(size: 20, weight: .bold, design: .rounded))
        }
        .padding(16)
        .background(CaptroScanPalette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 8))

        Spacer(minLength: 0)

        Button(action: purchaseCreditsAndVerify) {
          HStack(spacing: 9) {
            if isPurchasing { ProgressView().tint(.white) }
            else { Image(systemName: "cart.fill") }
            Text(isPurchasing ? "Confirming Purchase…" : "Buy Credits & Continue")
          }
          .captroPrimaryButtonLabel()
        }
        .buttonStyle(.miraPress)
        .disabled(isPurchasing)

        Button("Not Now") { showingCreditPurchase = false }
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(CaptroScanPalette.secondaryInk)
          .frame(maxWidth: .infinity)
      }
      .padding(24)
      .background(CaptroScanPalette.background.ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
    }
  }

  private func detailsSheet(_ result: CaptroScanVerificationResult) -> some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          detailSection("Document") {
            optionalDetail("Business", result.business?.name)
            optionalDetail(result.documentType == "invoice" ? "Invoice number" : "Receipt number", result.documentNumber)
            optionalDetail("Reference", result.transactionReference)
            optionalDetail("Date", joinedDateTime(result.issueDate, time: result.time))
            optionalDetail("Due date", result.dueDate)
            optionalDetail("Phone", result.business?.phone)
            optionalDetail("Store", result.business?.storeNumber)
          }

          if !result.items.isEmpty {
            detailSection(result.documentType == "invoice" ? "Line Items" : "Items") {
              ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 12) {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(item.description?.nonEmpty ?? "Item")
                      .font(.system(size: 14, weight: .semibold))
                    if let quantity = item.quantity?.nonEmpty {
                      Text("Qty \(quantity)")
                        .font(.system(size: 12))
                        .foregroundStyle(CaptroScanPalette.secondaryInk)
                    }
                  }
                  Spacer()
                  Text(money(item.total ?? item.unitPrice, currency: result.currency))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .padding(.vertical, 5)
              }
            }
          }

          detailSection("Totals") {
            optionalMoneyDetail("Subtotal", result.subtotal, currency: result.currency)
            optionalMoneyDetail("Discount", result.discount, currency: result.currency)
            optionalMoneyDetail("Tax", result.tax, currency: result.currency)
            optionalMoneyDetail("Fees", result.fees, currency: result.currency)
            optionalMoneyDetail("Total", result.total, currency: result.currency, emphasized: true)
          }

          if result.payment?.method?.nonEmpty != nil || result.payment?.lastFour?.nonEmpty != nil {
            detailSection("Payment") {
              optionalDetail("Method", result.payment?.method)
              if let lastFour = result.payment?.lastFour?.nonEmpty {
                optionalDetail("Card", "•••• \(lastFour)")
              }
            }
          }

          if result.customer?.name?.nonEmpty != nil || result.customer?.address?.nonEmpty != nil || result.paymentTerms?.nonEmpty != nil {
            detailSection("Invoice Details") {
              optionalDetail("Bill to", result.customer?.name)
              optionalDetail("Address", result.customer?.address)
              optionalDetail("Terms", result.paymentTerms)
            }
          }

          if !result.barcodes.isEmpty {
            detailSection("Barcode / QR") {
              ForEach(Array(result.barcodes.enumerated()), id: \.offset) { _, barcode in
                optionalDetail(barcode.type?.nonEmpty ?? "Code", barcode.data)
              }
            }
          }
        }
        .padding(20)
      }
      .background(CaptroScanPalette.background.ignoresSafeArea())
      .navigationTitle("Verification Details")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { showingDetails = false }
        }
      }
    }
  }

  private func proofSheet(_ proof: CaptroScanProof) -> some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 20) {
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 48, weight: .semibold))
          .foregroundStyle(CaptroScanPalette.forest)
        Text("Captro Proof")
          .font(.system(size: 28, weight: .bold))
        Text("This private proof records the completed verification without exposing the original receipt or invoice.")
          .font(.system(size: 15))
          .foregroundStyle(CaptroScanPalette.secondaryInk)
        Divider()
        optionalDetail("Proof ID", proof.proofId)
        optionalDetail("Business", proof.summary.businessName)
        optionalDetail("Document", proof.summary.documentNumber)
        optionalDetail("Date", proof.summary.issueDate)
        optionalMoneyDetail("Total", proof.summary.total, currency: proof.summary.currency, emphasized: true)
        Spacer()
      }
      .padding(24)
      .background(CaptroScanPalette.background.ignoresSafeArea())
      .navigationTitle("View Proof")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { showingProof = false }
        }
      }
    }
  }

  private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title.uppercased())
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(CaptroScanPalette.secondaryInk)
      VStack(alignment: .leading, spacing: 10) { content() }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CaptroScanPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CaptroScanPalette.line, lineWidth: 1))
    }
  }

  @ViewBuilder
  private func optionalDetail(_ label: String, _ value: String?) -> some View {
    if let value = value?.nonEmpty {
      HStack(alignment: .top, spacing: 12) {
        Text(label)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(CaptroScanPalette.secondaryInk)
          .frame(width: 100, alignment: .leading)
        Text(value)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(CaptroScanPalette.ink)
          .textSelection(.enabled)
        Spacer(minLength: 0)
      }
    }
  }

  @ViewBuilder
  private func optionalMoneyDetail(
    _ label: String,
    _ value: String?,
    currency: String?,
    emphasized: Bool = false
  ) -> some View {
    if let value = value?.nonEmpty {
      HStack {
        Text(label)
          .font(.system(size: emphasized ? 15 : 13, weight: emphasized ? .bold : .medium))
        Spacer()
        Text(money(value, currency: currency))
          .font(.system(size: emphasized ? 18 : 13, weight: emphasized ? .bold : .semibold, design: .rounded))
      }
      .foregroundStyle(CaptroScanPalette.ink)
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )
  }

  private func beginScan() {
    guard VNDocumentCameraViewController.isSupported else {
      errorMessage = "Document scanning is unavailable on this device. Import a PDF or image instead."
      return
    }
    showingScanner = true
  }

  private func beginImport() {
    showingImporter = true
  }

  private func handleScannedPages(_ scanResult: Result<[Data], Error>) {
    do {
      select(try CaptroLocalDocument.scanned(pages: scanResult.get()))
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func handleImportedURLs(_ importResult: Result<[URL], Error>) {
    do {
      guard let url = try importResult.get().first else { return }
      select(try CaptroLocalDocument.imported(url: url))
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func loadPhoto(_ item: PhotosPickerItem) async {
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        throw CaptroLocalDocumentError.inaccessible
      }
      select(try CaptroLocalDocument.photoImported(data: data))
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func select(_ document: CaptroLocalDocument) {
    selectedDocument = document
    detectedType = nil
    result = nil
    proof = nil
    idempotencyKey = "scan:\(document.sha256Hex):\(UUID().uuidString)"
    isDetecting = true
    Task {
      let type = await CaptroDocumentTypeDetector.detect(document)
      guard selectedDocument?.id == document.id else { return }
      detectedType = type
      isDetecting = false
    }
  }

  private func clearSelection() {
    selectedDocument = nil
    detectedType = nil
    idempotencyKey = nil
    selectedPhoto = nil
    result = nil
    proof = nil
    isDetecting = false
    isVerifying = false
  }

  private func beginVerification() {
    guard !isVerifying, detectedType == .receipt || detectedType == .invoice else { return }
    if purchase.balanceCents < purchase.verificationPriceCents {
      showingCreditPurchase = true
      return
    }
    submitVerification()
  }

  private func purchaseCreditsAndVerify() {
    guard !isPurchasing else { return }
    isPurchasing = true
    Task {
      defer { isPurchasing = false }
      do {
        let purchased = try await purchase.purchaseCreditPack()
        guard purchased else { return }
        showingCreditPurchase = false
        submitVerification()
      } catch {
        showingCreditPurchase = false
        errorMessage = error.localizedDescription
      }
    }
  }

  private func submitVerification() {
    guard let document = selectedDocument,
          let detectedType,
          detectedType != .unsupported,
          let idempotencyKey,
          !isVerifying else { return }
    isVerifying = true
    Task {
      defer { isVerifying = false }
      do {
        var response = try await api.verifyCaptroDocument(
          document,
          detectedType: detectedType,
          idempotencyKey: idempotencyKey
        )
        if !response.isComplete {
          response = try await awaitCompletedVerification(response)
        }
        result = response
        try? await purchase.refreshBalance()
      } catch {
        if creditsRequired(error) {
          try? await purchase.refreshBalance()
          showingCreditPurchase = true
        } else {
          errorMessage = error.localizedDescription
          try? await purchase.refreshBalance()
        }
      }
    }
  }

  private func awaitCompletedVerification(_ initial: CaptroScanVerificationResult) async throws -> CaptroScanVerificationResult {
    var latest = initial
    for _ in 0..<20 {
      try await Task.sleep(nanoseconds: 1_500_000_000)
      latest = try await api.captroScanVerification(id: initial.verificationId)
      if latest.isComplete { return latest }
    }
    return latest
  }

  private func creditsRequired(_ error: Error) -> Bool {
    guard let apiError = error as? MIRAAPIError,
          case .server(let status, let code, _) = apiError else { return false }
    return status == 402 || code == "SCAN_CREDITS_REQUIRED"
  }

  private func loadProof(_ proofID: String) {
    Task {
      do {
        proof = try await api.captroScanProof(id: proofID)
        showingProof = true
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func displayAddress(_ address: CaptroScanAddress?) -> String? {
    guard let address else { return nil }
    if let original = address.original?.nonEmpty { return original }
    let locality = [address.city?.nonEmpty, address.state?.nonEmpty, address.postalCode?.nonEmpty]
      .compactMap { $0 }
      .joined(separator: " ")
    return [address.street?.nonEmpty, locality.nonEmpty, address.country?.nonEmpty]
      .compactMap { $0 }
      .joined(separator: "\n")
      .nonEmpty
  }

  private func documentTypeName(_ type: String) -> String {
    type == "invoice" ? "Invoice" : "Receipt"
  }

  private func joinedDateTime(_ date: String?, time: String?) -> String? {
    [date?.nonEmpty, time?.nonEmpty].compactMap { $0 }.joined(separator: " · ").nonEmpty
  }

  private func money(_ value: String?, currency: String?) -> String {
    guard let value = value?.nonEmpty else { return "—" }
    guard let number = Decimal(string: value) else { return value }
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency?.nonEmpty ?? "USD"
    formatter.maximumFractionDigits = 2
    return formatter.string(from: number as NSDecimalNumber) ?? "\(currency ?? "") \(value)".trimmingCharacters(in: .whitespaces)
  }

  private func billingCopy(_ state: String) -> String {
    switch state {
    case "refunded": return "Verification credit restored"
    case "credited": return "Existing verification · no new charge"
    case "not_charged": return "Not charged"
    default: return "Billing status: \(state.replacingOccurrences(of: "_", with: " "))"
    }
  }
}

private enum CaptroScanPalette {
  static let background = Color(red: 0.952, green: 0.953, blue: 0.978)
  static let canvas = Color(red: 0.985, green: 0.982, blue: 0.965)
  static let paper = Color.white
  static let ink = Color(red: 0.07, green: 0.07, blue: 0.065)
  static let secondaryInk = Color(red: 0.33, green: 0.34, blue: 0.36)
  static let forest = Color(red: 0.08, green: 0.24, blue: 0.15)
  static let line = Color.black.opacity(0.10)
  static let dot = Color(red: 0.57, green: 0.58, blue: 0.63).opacity(0.45)
}

private extension View {
  func captroPrimaryButtonLabel() -> some View {
    self
      .font(.system(size: 16, weight: .bold))
      .foregroundStyle(Color.white)
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(CaptroScanPalette.forest)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  func captroSecondaryButtonLabel() -> some View {
    self
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(CaptroScanPalette.ink)
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(CaptroScanPalette.paper)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(CaptroScanPalette.line, lineWidth: 1))
  }
}

private extension Optional where Wrapped == String {
  var nonEmpty: String? {
    guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
  }
}

private extension String {
  var nonEmpty: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
