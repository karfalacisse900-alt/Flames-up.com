import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

public struct CaptroScanView: View {
  let api: MIRAAPIClient
  let onClose: () -> Void

  @State private var stage: CaptroReceiptStage = .capture
  @State private var selectedDocument: CaptroLocalDocument?
  @State private var review: CaptroReceiptReview?
  @State private var reward: CaptroReceiptRewardResult?
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var ratings: [String: Int] = [:]
  @State private var note = ""
  @State private var reviewIdempotencyKey: String?
  @State private var feedbackIdempotencyKey: String?
  @State private var isProcessingReview = false
  @State private var isSubmittingFeedback = false
  @State private var showingImporter = false
  @State private var showingOriginal = false
  @State private var captureRequestID = 0
  @State private var torchEnabled = false
  @State private var cameraAvailable = true
  @State private var cameraStatus: CaptroCameraDocumentStatus = .looking
  @State private var reviewFailure: String?
  @State private var errorMessage: String?

  public init(api: MIRAAPIClient, onClose: @escaping () -> Void = {}) {
    self.api = api
    self.onClose = onClose
  }

  public var body: some View {
    NavigationStack {
      stageContent
        .background(CaptroReceiptPalette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
    .toolbar(.hidden, for: .tabBar)
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      Task { await loadPhoto(item) }
    }
    .fileImporter(
      isPresented: $showingImporter,
      allowedContentTypes: [.pdf, .image],
      allowsMultipleSelection: false,
      onCompletion: handleImportedURLs
    )
    .sheet(isPresented: $showingOriginal) {
      if let selectedDocument {
        CaptroLocalDocumentViewer(document: selectedDocument)
      }
    }
    .alert("Captro Scan", isPresented: errorBinding) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "Captro could not complete that request.")
    }
  }

  @ViewBuilder
  private var stageContent: some View {
    switch stage {
    case .capture:
      captureStage
    case .review:
      reviewStage
    case .feedback:
      feedbackStage
    case .success:
      successStage
    }
  }

  private var captureStage: some View {
    ZStack {
      if cameraAvailable {
        CaptroReceiptCameraView(
          captureRequestID: captureRequestID,
          torchEnabled: torchEnabled,
          onCapture: handleCameraCapture,
          onStatusChange: { cameraStatus = $0 },
          onAvailabilityChange: { cameraAvailable = $0 }
        )
        .ignoresSafeArea()
      } else {
        CaptroReceiptPalette.background.ignoresSafeArea()
        VStack(spacing: 12) {
          Image(systemName: "camera.fill")
            .font(.system(size: 34, weight: .light))
          Text("Camera unavailable")
            .font(.system(size: 19, weight: .semibold))
          Text("Choose a receipt or invoice from Photos or Files.")
            .font(.system(size: 14, weight: .regular))
            .multilineTextAlignment(.center)
        }
        .foregroundStyle(CaptroReceiptPalette.secondaryInk)
        .padding(.horizontal, 36)
      }

      VStack(spacing: 0) {
        HStack {
          cameraCircleButton(systemImage: "xmark", accessibilityLabel: "Close Scan") {
            torchEnabled = false
            onClose()
          }
          Spacer()
          if cameraAvailable {
            cameraCircleButton(
              systemImage: torchEnabled ? "bolt.fill" : "bolt.slash.fill",
              accessibilityLabel: torchEnabled ? "Turn flash off" : "Turn flash on"
            ) {
              torchEnabled.toggle()
            }
          }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)

        Spacer()

        if cameraAvailable {
          Text(cameraStatus.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(CaptroReceiptPalette.ink)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color.white.opacity(0.92))
            .clipShape(Capsule())
            .padding(.bottom, 18)
            .accessibilityLabel(cameraStatus.title)
        }

        HStack(alignment: .center) {
          PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
            cameraImportControl(systemImage: "photo.on.rectangle", label: "Photos")
          }
          .accessibilityLabel("Choose from Photos")

          Spacer()

          Button(action: captureDocument) {
            ZStack {
              Circle()
                .stroke(Color.white.opacity(cameraAvailable ? 1 : 0.4), lineWidth: 4)
                .frame(width: 78, height: 78)
              Circle()
                .fill(Color.white.opacity(cameraAvailable ? 0.96 : 0.4))
                .frame(width: 64, height: 64)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .disabled(!cameraAvailable || cameraStatus == .capturing)
          .accessibilityLabel("Capture document")

          Spacer()

          Button(action: beginImport) {
            cameraImportControl(systemImage: "doc", label: "Files")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Import from Files")
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
      }
    }
  }

  private func cameraCircleButton(
    systemImage: String,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(CaptroReceiptPalette.ink)
        .frame(width: 44, height: 44)
        .background(Color.white.opacity(0.94))
        .clipShape(Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }

  private func cameraImportControl(systemImage: String, label: String) -> some View {
    VStack(spacing: 6) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(CaptroReceiptPalette.ink)
        .frame(width: 44, height: 44)
        .background(Color.white.opacity(0.94))
        .clipShape(Circle())
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(cameraAvailable ? Color.white : CaptroReceiptPalette.secondaryInk)
    }
    .frame(width: 64, height: 66)
  }

  private var reviewStage: some View {
    VStack(spacing: 0) {
      reviewTopBar
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing: 18) {
            Spacer(minLength: max(24, geometry.size.height * 0.07))
            reviewDocument(width: min(geometry.size.width * 0.62, 300))
            reviewStatus
            if review != nil {
              Button {
                showingOriginal = true
              } label: {
                Label("View original", systemImage: "arrow.up.left.and.arrow.down.right")
                  .font(.system(size: 12, weight: .medium))
                  .foregroundStyle(CaptroReceiptPalette.secondaryInk)
                  .frame(minHeight: 44)
              }
              .buttonStyle(.plain)
              .accessibilityHint("Opens the privately stored document preview")
            }
            Spacer(minLength: 28)
          }
          .frame(maxWidth: .infinity)
          .frame(minHeight: geometry.size.height)
          .padding(.horizontal, 20)
        }
        .miraScrollFeel(.feed)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      reviewBottomBar
    }
  }

  private var reviewTopBar: some View {
    HStack {
      Button(action: resetFlow) {
        Image(systemName: "xmark")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Close review")

      Spacer()
      Text("Review")
        .font(.system(size: 17, weight: .semibold))
      Spacer()

      Menu {
        if review != nil {
          Button {
            showingOriginal = true
          } label: {
            Label("View original", systemImage: "doc.text.magnifyingglass")
          }
        }
        Button(action: resetFlow) {
          Label("Scan another", systemImage: "arrow.counterclockwise")
        }
      } label: {
        Image(systemName: "gearshape.fill")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Review options")
    }
    .foregroundStyle(CaptroReceiptPalette.ink)
    .padding(.horizontal, 10)
    .frame(height: 54)
  }

  @ViewBuilder
  private func reviewDocument(width: CGFloat) -> some View {
    if let review, !isProcessingReview {
      digitalReceiptPreview(review, width: width)
    } else if let selectedDocument {
      originalReceiptPreview(selectedDocument, width: width)
    }
  }

  private func originalReceiptPreview(_ document: CaptroLocalDocument, width: CGFloat) -> some View {
    Group {
      if let image = document.firstPageImage {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else {
        VStack(spacing: 12) {
          Image(systemName: "doc.richtext")
            .font(.system(size: 38, weight: .ultraLight))
          Text("Document preview")
            .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(CaptroReceiptPalette.secondaryInk)
        .frame(height: 320)
      }
    }
    .frame(width: width, maxHeight: 440)
    .padding(8)
    .background(CaptroReceiptPalette.paper)
    .overlay(Rectangle().stroke(CaptroReceiptPalette.line.opacity(0.7), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 8)
    .accessibilityLabel("Scanned document preview")
  }

  private func digitalReceiptPreview(_ review: CaptroReceiptReview, width: CGFloat) -> some View {
    VStack(spacing: 16) {
      Circle()
        .fill(CaptroReceiptPalette.reward.opacity(0.12))
        .frame(width: 34, height: 34)
        .overlay(
          Text(review.documentType == "invoice" ? "IN" : "RC")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(CaptroReceiptPalette.reward)
        )

      VStack(spacing: 4) {
        Text(review.merchantName?.nonEmpty ?? (review.documentType == "invoice" ? "Invoice" : "Receipt"))
          .font(.system(size: 13, weight: .semibold))
          .multilineTextAlignment(.center)
          .lineLimit(2)
        if let date = purchaseDateLine(review) {
          Text(date)
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(CaptroReceiptPalette.secondaryInk)
        }
      }

      if !review.items.isEmpty {
        VStack(spacing: 7) {
          ForEach(Array(review.items.prefix(5).enumerated()), id: \.offset) { _, item in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(item.description?.nonEmpty ?? "Item")
                .lineLimit(2)
              Spacer(minLength: 8)
              if let total = item.total?.nonEmpty ?? item.unitPrice?.nonEmpty {
                Text(money(total, currency: review.currency)).monospacedDigit()
              }
            }
            .font(.system(size: 9, weight: .regular))
          }
        }
      }

      Divider().overlay(CaptroReceiptPalette.line)
      VStack(spacing: 6) {
        receiptAmountRow("Subtotal", value: review.subtotal, currency: review.currency)
        receiptAmountRow("Tax", value: review.tax, currency: review.currency)
        receiptAmountRow("Total", value: review.total, currency: review.currency, emphasized: true)
      }
    }
    .foregroundStyle(CaptroReceiptPalette.ink)
    .padding(.horizontal, 18)
    .padding(.vertical, 22)
    .frame(width: width, minHeight: 330)
    .background(CaptroReceiptPalette.paper)
    .overlay(Rectangle().stroke(CaptroReceiptPalette.line.opacity(0.6), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 8)
    .onTapGesture { showingOriginal = true }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(review.documentType.capitalized) from \(review.merchantName ?? "unknown merchant")")
    .accessibilityHint("Double tap to view the original document")
  }

  @ViewBuilder
  private func receiptAmountRow(
    _ label: String,
    value: String?,
    currency: String?,
    emphasized: Bool = false
  ) -> some View {
    if let value = value?.nonEmpty {
      HStack {
        Text(label)
        Spacer()
        Text(money(value, currency: currency)).monospacedDigit()
      }
      .font(.system(size: emphasized ? 11 : 9, weight: emphasized ? .semibold : .regular))
    }
  }

  @ViewBuilder
  private var reviewStatus: some View {
    if isProcessingReview {
      statusLine("Processing your document...", progress: true)
    } else if let review, review.duplicate {
      VStack(spacing: 6) {
        statusLine("Already submitted", systemImage: "clock.arrow.circlepath")
        Text("This document has already been submitted.")
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(CaptroReceiptPalette.secondaryInk)
      }
    } else if let review, review.rewardEligible, review.verdict == "Verified" {
      VStack(spacing: 6) {
        statusLine("Verified", systemImage: "checkmark.circle.fill", accent: CaptroReceiptPalette.reward)
        Text("\(review.documentType.capitalized) ready")
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(CaptroReceiptPalette.secondaryInk)
      }
    } else if review != nil {
      VStack(spacing: 6) {
        statusLine("Couldn't Verify", systemImage: "exclamationmark.circle")
        Text("Captro couldn't verify this document with the available information.")
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(CaptroReceiptPalette.secondaryInk)
          .multilineTextAlignment(.center)
      }
    } else if let reviewFailure {
      VStack(spacing: 6) {
        statusLine("Couldn't process document", systemImage: "exclamationmark.circle")
        Text(reviewFailure)
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(CaptroReceiptPalette.secondaryInk)
          .multilineTextAlignment(.center)
      }
    }
  }

  private func statusLine(
    _ text: String,
    progress: Bool = false,
    systemImage: String? = nil,
    accent: Color = CaptroReceiptPalette.secondaryInk
  ) -> some View {
    HStack(spacing: 9) {
      if progress {
        ProgressView().tint(CaptroReceiptPalette.reward)
      } else if let systemImage {
        Image(systemName: systemImage).foregroundStyle(accent)
      }
      Text(text)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(CaptroReceiptPalette.ink)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var reviewBottomBar: some View {
    Group {
      if isProcessingReview {
        HStack(spacing: 10) {
          ProgressView().tint(.white)
          Text("Processing")
        }
        .captroReceiptPrimaryButton()
        .opacity(0.72)
      } else if review?.rewardEligible == true, review?.verdict == "Verified" {
        Button(action: continueToFeedback) {
          Text("Next").captroReceiptPrimaryButton()
        }
        .buttonStyle(.miraPress)
      } else {
        Button(action: resetFlow) {
          Text(review?.duplicate == true ? "Scan Another" : "Try Again")
            .captroReceiptPrimaryButton()
        }
        .buttonStyle(.miraPress)
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 10)
    .padding(.bottom, 10)
    .background(CaptroReceiptPalette.background.opacity(0.98))
  }

  private var feedbackStage: some View {
    VStack(spacing: 0) {
      feedbackTopBar
      ScrollView {
        VStack(alignment: .leading, spacing: 26) {
          VStack(alignment: .leading, spacing: 8) {
            Text(review?.merchantName?.nonEmpty ?? "Your purchase")
              .font(.system(size: 24, weight: .bold))
              .foregroundStyle(CaptroReceiptPalette.ink)
            Text("Tell us about your purchase to complete this submission and earn \(money(cents: review?.rewardCents ?? 0)).")
              .font(.system(size: 14, weight: .regular))
              .foregroundStyle(CaptroReceiptPalette.secondaryInk)
              .fixedSize(horizontal: false, vertical: true)
          }

          ForEach(feedbackQuestions) { question in
            ratingQuestion(question)
          }

          VStack(alignment: .leading, spacing: 10) {
            Text("Add a short note (optional)")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(CaptroReceiptPalette.ink)
            ZStack(alignment: .topLeading) {
              if note.isEmpty {
                Text("What stood out?")
                  .font(.system(size: 14))
                  .foregroundStyle(CaptroReceiptPalette.secondaryInk.opacity(0.7))
                  .padding(.horizontal, 13)
                  .padding(.vertical, 14)
              }
              TextEditor(text: $note)
                .font(.system(size: 14, weight: .regular))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 104)
            }
            .background(CaptroReceiptPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CaptroReceiptPalette.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
          }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
      }
      .miraScrollFeel(.feed)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      Button(action: submitFeedback) {
        HStack(spacing: 9) {
          if isSubmittingFeedback {
            ProgressView().tint(.white)
          }
          Text(isSubmittingFeedback ? "Submitting" : "Submit")
        }
        .captroReceiptPrimaryButton()
      }
      .buttonStyle(.miraPress)
      .disabled(!allQuestionsAnswered || isSubmittingFeedback)
      .opacity(allQuestionsAnswered && !isSubmittingFeedback ? 1 : 0.48)
      .padding(.horizontal, 22)
      .padding(.vertical, 10)
      .background(CaptroReceiptPalette.background.opacity(0.98))
    }
  }

  private var feedbackTopBar: some View {
    HStack {
      Button {
        stage = .review
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 44, height: 44)
      }
      .accessibilityLabel("Back to review")
      Spacer()
      Text("Purchase feedback")
        .font(.system(size: 17, weight: .semibold))
      Spacer()
      Color.clear.frame(width: 44, height: 44)
    }
    .foregroundStyle(CaptroReceiptPalette.ink)
    .padding(.horizontal, 10)
    .frame(height: 54)
  }

  private func ratingQuestion(_ question: CaptroFeedbackQuestion) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(question.title)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(CaptroReceiptPalette.ink)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        ForEach(1...5, id: \.self) { value in
          Button {
            CaptroHaptics.light()
            ratings[question.key] = value
          } label: {
            Text("\(value)")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(ratings[question.key] == value ? Color.white : CaptroReceiptPalette.ink)
              .frame(maxWidth: .infinity)
              .frame(height: 42)
              .background(ratings[question.key] == value ? CaptroReceiptPalette.reward : CaptroReceiptPalette.surface)
              .clipShape(Capsule())
              .overlay(Capsule().stroke(CaptroReceiptPalette.line, lineWidth: ratings[question.key] == value ? 0 : 1))
          }
          .buttonStyle(.miraPress)
          .accessibilityLabel("\(question.title), \(value) out of 5")
          .accessibilityValue(ratings[question.key] == value ? "Selected" : "Not selected")
        }
      }

      HStack {
        Text("Poor")
        Spacer()
        Text("Excellent")
      }
      .font(.system(size: 11, weight: .regular))
      .foregroundStyle(CaptroReceiptPalette.secondaryInk)
    }
  }

  private var successStage: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 36)
      VStack(spacing: 18) {
        Circle()
          .fill(CaptroReceiptPalette.reward.opacity(0.11))
          .frame(width: 86, height: 86)
          .overlay(
            Image(systemName: "checkmark")
              .font(.system(size: 34, weight: .semibold))
              .foregroundStyle(CaptroReceiptPalette.reward)
          )

        VStack(spacing: 8) {
          Text("Thanks!")
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(CaptroReceiptPalette.ink)
          if let amount = reward?.amountCents {
            Text("You earned \(money(cents: amount))")
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(CaptroReceiptPalette.reward)
          }
          Text("Your receipt earnings are private and visible only in your account.")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(CaptroReceiptPalette.secondaryInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let reward {
          VStack(spacing: 6) {
            Text("AVAILABLE BALANCE")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(CaptroReceiptPalette.secondaryInk)
            Text(money(cents: reward.availableBalanceCents))
              .font(.system(size: 30, weight: .semibold, design: .rounded))
              .foregroundStyle(CaptroReceiptPalette.ink)
          }
          .padding(.top, 18)
        }
      }
      .frame(maxWidth: 420)
      .padding(.horizontal, 28)
      Spacer()

      Button(action: resetFlow) {
        Text("Scan Another").captroReceiptPrimaryButton()
      }
      .buttonStyle(.miraPress)
      .padding(.horizontal, 22)
      .padding(.bottom, 18)
    }
  }

  private var feedbackQuestions: [CaptroFeedbackQuestion] {
    switch review?.category ?? .general {
    case .restaurantFood:
      return [
        .init(key: "quality", title: "How was the food or drink quality?"),
        .init(key: "cleanliness", title: "How clean was the location?"),
        .init(key: "speed", title: "How fast was the service?"),
        .init(key: "service", title: "How was the staff?"),
        .init(key: "value", title: "Was it worth the price?"),
        .init(key: "overall", title: "Overall experience?"),
      ]
    case .productRetail:
      return [
        .init(key: "quality", title: "How was the product quality?"),
        .init(key: "expectations", title: "Did the product match your expectations?"),
        .init(key: "value", title: "Was it worth the price?"),
        .init(key: "speed", title: "How fast was checkout?"),
        .init(key: "organization", title: "How clean and organized was the store?"),
        .init(key: "overall", title: "Overall experience?"),
      ]
    case .grocery:
      return [
        .init(key: "freshness", title: "How fresh were the products?"),
        .init(key: "cleanliness", title: "How clean was the store?"),
        .init(key: "stock", title: "Were the items in stock?"),
        .init(key: "speed", title: "How fast was checkout?"),
        .init(key: "value", title: "Were prices reasonable?"),
        .init(key: "overall", title: "Overall experience?"),
      ]
    case .serviceBusiness:
      return [
        .init(key: "professionalism", title: "How professional was the service?"),
        .init(key: "speed", title: "How quickly was the service completed?"),
        .init(key: "result", title: "Was the result what you expected?"),
        .init(key: "value", title: "Was it worth the price?"),
        .init(key: "overall", title: "Overall experience?"),
      ]
    case .general:
      return [
        .init(key: "quality", title: "Quality"),
        .init(key: "service", title: "Service"),
        .init(key: "value", title: "Value"),
        .init(key: "overall", title: "Overall experience"),
      ]
    }
  }

  private var allQuestionsAnswered: Bool {
    feedbackQuestions.allSatisfy { ratings[$0.key] != nil }
  }

  private var errorBinding: Binding<Bool> {
    Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )
  }

  private func captureDocument() {
    guard cameraAvailable, cameraStatus != .capturing else { return }
    captureRequestID += 1
  }

  private func beginImport() {
    showingImporter = true
  }

  private func handleCameraCapture(_ result: Result<Data, Error>) {
    do {
      select(try CaptroLocalDocument.scanned(pages: [result.get()]))
    } catch {
      cameraStatus = .looking
      errorMessage = error.localizedDescription
    }
  }

  private func handleImportedURLs(_ result: Result<[URL], Error>) {
    do {
      guard let url = try result.get().first else { return }
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
    torchEnabled = false
    selectedDocument = document
    review = nil
    reward = nil
    ratings = [:]
    note = ""
    reviewFailure = nil
    reviewIdempotencyKey = "receipt-review:\(document.sha256Hex):\(UUID().uuidString)"
    feedbackIdempotencyKey = nil
    stage = .review
    processReview(document)
  }

  private func processReview(_ document: CaptroLocalDocument) {
    guard !isProcessingReview, let reviewIdempotencyKey else { return }
    isProcessingReview = true
    reviewFailure = nil
    Task {
      defer { isProcessingReview = false }
      do {
        review = try await api.reviewCaptroReceipt(document, idempotencyKey: reviewIdempotencyKey)
      } catch {
        reviewFailure = processingMessage(for: error)
      }
    }
  }

  private func processingMessage(for error: Error) -> String {
    let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    if detail.localizedCaseInsensitiveContains("upload") {
      return "Couldn't upload the document. Try again."
    }
    if detail.localizedCaseInsensitiveContains("supported") {
      return "This does not appear to be a supported receipt or invoice."
    }
    return "We couldn't process this document. Try another photo or file."
  }

  private func continueToFeedback() {
    guard review?.rewardEligible == true, review?.verdict == "Verified" else { return }
    feedbackIdempotencyKey = feedbackIdempotencyKey
      ?? "receipt-feedback:\(review?.receiptId ?? UUID().uuidString):\(UUID().uuidString)"
    stage = .feedback
  }

  private func submitFeedback() {
    guard let review, let feedbackIdempotencyKey, allQuestionsAnswered, !isSubmittingFeedback else { return }
    isSubmittingFeedback = true
    Task {
      defer { isSubmittingFeedback = false }
      do {
        reward = try await api.submitCaptroReceiptFeedback(
          receiptId: review.receiptId,
          ratings: ratings,
          note: note,
          idempotencyKey: feedbackIdempotencyKey
        )
        CaptroHaptics.success()
        stage = .success
      } catch {
        errorMessage = "Your submission is still pending. Tap Submit again to retry safely."
      }
    }
  }

  private func resetFlow() {
    stage = .capture
    selectedDocument = nil
    review = nil
    reward = nil
    selectedPhoto = nil
    ratings = [:]
    note = ""
    reviewIdempotencyKey = nil
    feedbackIdempotencyKey = nil
    isProcessingReview = false
    isSubmittingFeedback = false
    reviewFailure = nil
    cameraStatus = .looking
  }

  private func purchaseDateLine(_ review: CaptroReceiptReview) -> String? {
    [review.purchaseDate?.nonEmpty, review.purchaseTime?.nonEmpty]
      .compactMap { $0 }
      .joined(separator: " at ")
      .nonEmpty
  }

  private func money(_ value: String, currency: String?) -> String {
    guard let decimal = Decimal(string: value) else { return value }
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency?.nonEmpty ?? "USD"
    formatter.maximumFractionDigits = 2
    return formatter.string(from: decimal as NSDecimalNumber) ?? value
  }

  private func money(cents: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00"
  }
}

private enum CaptroReceiptStage {
  case capture
  case review
  case feedback
  case success
}

private struct CaptroFeedbackQuestion: Identifiable {
  let key: String
  let title: String
  var id: String { key }
}

private enum CaptroReceiptPalette {
  static let background = Color(red: 0.988, green: 0.988, blue: 0.982)
  static let surface = Color(red: 0.965, green: 0.966, blue: 0.958)
  static let paper = Color.white
  static let ink = Color(red: 0.07, green: 0.07, blue: 0.065)
  static let secondaryInk = Color(red: 0.37, green: 0.38, blue: 0.38)
  static let reward = Color(red: 0.08, green: 0.24, blue: 0.15)
  static let line = Color.black.opacity(0.10)
}

private struct CaptroLocalDocumentViewer: View {
  let document: CaptroLocalDocument
  @Environment(\.dismiss) private var dismiss
  @State private var scale: CGFloat = 1
  @State private var baseScale: CGFloat = 1

  var body: some View {
    NavigationStack {
      ScrollView([.horizontal, .vertical]) {
        Group {
          if let image = document.firstPageImage {
            Image(uiImage: image)
              .resizable()
              .scaledToFit()
              .scaleEffect(scale)
          } else {
            Image(systemName: "doc.richtext")
              .font(.system(size: 58, weight: .ultraLight))
              .foregroundStyle(CaptroReceiptPalette.secondaryInk)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 620)
        .padding(20)
        .gesture(
          MagnifyGesture()
            .onChanged { value in scale = min(max(baseScale * value.magnification, 1), 5) }
            .onEnded { _ in baseScale = scale }
        )
      }
      .background(CaptroReceiptPalette.background)
      .navigationTitle("Original document")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

private extension View {
  func captroReceiptPrimaryButton() -> some View {
    self
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(Color.white)
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(CaptroReceiptPalette.reward)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
