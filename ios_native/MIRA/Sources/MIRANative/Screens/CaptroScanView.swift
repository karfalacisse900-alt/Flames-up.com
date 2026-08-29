import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import VisionKit

public struct CaptroScanView: View {
  let api: MIRAAPIClient

  @State private var stage: CaptroReceiptStage = .capture
  @State private var selectedDocument: CaptroLocalDocument?
  @State private var detectedType: CaptroDetectedDocumentType?
  @State private var review: CaptroReceiptReview?
  @State private var reward: CaptroReceiptRewardResult?
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var ratings: [String: Int] = [:]
  @State private var note = ""
  @State private var reviewIdempotencyKey: String?
  @State private var feedbackIdempotencyKey: String?
  @State private var isDetecting = false
  @State private var isProcessingReview = false
  @State private var isSubmittingFeedback = false
  @State private var showingScanner = false
  @State private var showingImporter = false
  @State private var errorMessage: String?

  public init(api: MIRAAPIClient) {
    self.api = api
  }

  public var body: some View {
    NavigationStack {
      stageContent
        .background(CaptroReceiptPalette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      Task { await loadPhoto(item) }
    }
    .fullScreenCover(isPresented: $showingScanner) {
      CaptroDocumentScannerView(
        completion: { result in
          handleScannedPages(result)
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
    ScrollView {
      VStack(spacing: 28) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Scan")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(CaptroReceiptPalette.ink)
          Text("Scan a receipt or invoice")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(CaptroReceiptPalette.secondaryInk)
          Text("Captro reads the purchase and asks a few quick questions.")
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(CaptroReceiptPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        emptyReceiptPreview

        VStack(spacing: 12) {
          Button(action: beginScan) {
            Label("Scan Document", systemImage: "doc.viewfinder")
              .captroReceiptPrimaryButton()
          }
          .buttonStyle(.miraPress)

          HStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
              Label("Photos", systemImage: "photo.on.rectangle")
                .captroReceiptSecondaryButton()
            }
            .buttonStyle(.miraPress)

            Button(action: beginImport) {
              Label("Import", systemImage: "square.and.arrow.down")
                .captroReceiptSecondaryButton()
            }
            .buttonStyle(.miraPress)
          }
        }

        Label("Receipts are processed privately and never added to your public profile.", systemImage: "lock.fill")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(CaptroReceiptPalette.secondaryInk)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: 560)
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 34)
      .frame(maxWidth: .infinity)
    }
    .miraScrollFeel(.feed)
  }

  private var emptyReceiptPreview: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .fill(CaptroReceiptPalette.paper)
        .frame(width: 230, height: 310)
        .overlay(
          VStack(spacing: 14) {
            Circle()
              .fill(CaptroReceiptPalette.reward.opacity(0.15))
              .frame(width: 38, height: 38)
              .overlay(
                Image(systemName: "doc.text")
                  .font(.system(size: 16, weight: .medium))
                  .foregroundStyle(CaptroReceiptPalette.reward)
              )
            Text("RECEIPT")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(CaptroReceiptPalette.secondaryInk)
            VStack(spacing: 10) {
              receiptPlaceholderLine(width: 128)
              receiptPlaceholderLine(width: 154)
              receiptPlaceholderLine(width: 116)
              receiptPlaceholderLine(width: 145)
            }
            Spacer().frame(height: 18)
            Divider().frame(width: 150)
            HStack {
              Text("TOTAL")
              Spacer()
              Text("$0.00")
            }
            .font(.system(size: 11, weight: .semibold))
            .frame(width: 150)
            .foregroundStyle(CaptroReceiptPalette.ink)
          }
          .padding(.vertical, 34)
        )
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(CaptroReceiptPalette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 18, x: 0, y: 10)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 350)
    .accessibilityHidden(true)
  }

  private func receiptPlaceholderLine(width: CGFloat) -> some View {
    Capsule()
      .fill(CaptroReceiptPalette.line)
      .frame(width: width, height: 4)
  }

  private var reviewStage: some View {
    VStack(spacing: 0) {
      reviewTopBar
      ScrollView {
        VStack(spacing: 24) {
          if let document = selectedDocument {
            scannedReceiptPreview(document)
          }
          reviewStatus
          if let review {
            extractedPurchase(review)
          }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
      }
      .miraScrollFeel(.feed)
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
        Button(action: resetFlow) {
          Label("Scan another", systemImage: "arrow.counterclockwise")
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Review options")
    }
    .foregroundStyle(CaptroReceiptPalette.ink)
    .padding(.horizontal, 10)
    .frame(height: 54)
  }

  private func scannedReceiptPreview(_ document: CaptroLocalDocument) -> some View {
    Group {
      if let image = document.firstPageImage {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else {
        VStack(spacing: 12) {
          Image(systemName: "doc.richtext")
            .font(.system(size: 42, weight: .ultraLight))
          Text("Document preview")
            .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(CaptroReceiptPalette.secondaryInk)
      }
    }
    .frame(maxWidth: 286, maxHeight: 440)
    .padding(10)
    .background(CaptroReceiptPalette.paper)
    .overlay(RoundedRectangle(cornerRadius: 3).stroke(CaptroReceiptPalette.line, lineWidth: 1))
    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 9)
    .frame(maxWidth: .infinity)
    .accessibilityLabel("Scanned receipt preview")
  }

  @ViewBuilder
  private var reviewStatus: some View {
    if isDetecting {
      statusLine("Recognizing receipt or invoice", progress: true)
    } else if isProcessingReview {
      statusLine("Reading purchase details", progress: true)
    } else if let review, review.duplicate {
      statusLine("This receipt was already submitted", systemImage: "clock.arrow.circlepath")
    } else if let review, review.rewardEligible {
      statusLine("Ready for your feedback", systemImage: "checkmark.circle.fill")
    } else if detectedType == .unsupported {
      statusLine("Captro could not recognize this document", systemImage: "questionmark.circle")
    }
  }

  private func statusLine(_ text: String, progress: Bool = false, systemImage: String? = nil) -> some View {
    HStack(spacing: 10) {
      if progress {
        ProgressView().tint(CaptroReceiptPalette.reward)
      } else if let systemImage {
        Image(systemName: systemImage)
          .foregroundStyle(CaptroReceiptPalette.reward)
      }
      Text(text)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(CaptroReceiptPalette.secondaryInk)
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private func extractedPurchase(_ review: CaptroReceiptReview) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text(review.merchantName?.nonEmpty ?? (review.documentType == "invoice" ? "Invoice" : "Receipt"))
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(CaptroReceiptPalette.ink)
        if let date = purchaseDateLine(review) {
          Text(date)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(CaptroReceiptPalette.secondaryInk)
        }
      }

      if !review.items.isEmpty {
        VStack(spacing: 9) {
          ForEach(Array(review.items.prefix(6).enumerated()), id: \.offset) { _, item in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text(item.description?.nonEmpty ?? "Item")
                .lineLimit(2)
              Spacer(minLength: 12)
              if let total = item.total?.nonEmpty ?? item.unitPrice?.nonEmpty {
                Text(money(total, currency: review.currency))
                  .monospacedDigit()
              }
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(CaptroReceiptPalette.ink)
          }
        }
      }

      Divider().overlay(CaptroReceiptPalette.line)
      VStack(spacing: 8) {
        amountRow("Subtotal", value: review.subtotal, currency: review.currency)
        amountRow("Tax", value: review.tax, currency: review.currency)
        amountRow("Total", value: review.total, currency: review.currency, emphasized: true)
      }
    }
    .frame(maxWidth: 330, alignment: .leading)
    .padding(.top, 2)
  }

  @ViewBuilder
  private func amountRow(_ label: String, value: String?, currency: String?, emphasized: Bool = false) -> some View {
    if let value = value?.nonEmpty {
      HStack {
        Text(label)
        Spacer()
        Text(money(value, currency: currency)).monospacedDigit()
      }
      .font(.system(size: emphasized ? 14 : 12, weight: emphasized ? .semibold : .regular))
      .foregroundStyle(CaptroReceiptPalette.ink)
    }
  }

  private var reviewBottomBar: some View {
    VStack(spacing: 8) {
      if review?.duplicate == true {
        Button(action: resetFlow) {
          Text("Scan Another").captroReceiptPrimaryButton()
        }
        .buttonStyle(.miraPress)
      } else {
        Button(action: continueToFeedback) {
          HStack(spacing: 9) {
            Text("Next")
            Image(systemName: "arrow.right")
          }
          .captroReceiptPrimaryButton()
        }
        .buttonStyle(.miraPress)
        .disabled(review?.rewardEligible != true || isDetecting || isProcessingReview)
        .opacity(review?.rewardEligible == true ? 1 : 0.48)
      }
      Button("Back", action: resetFlow)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(CaptroReceiptPalette.secondaryInk)
        .frame(minWidth: 80, minHeight: 36)
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 10)
    .background(.ultraThinMaterial)
  }

  private var feedbackStage: some View {
    VStack(spacing: 0) {
      feedbackTopBar
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(alignment: .leading, spacing: 5) {
            Text(review?.merchantName?.nonEmpty ?? "Your purchase")
              .font(.system(size: 25, weight: .bold))
              .foregroundStyle(CaptroReceiptPalette.ink)
            Text(review?.category.title ?? "Purchase")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(CaptroReceiptPalette.secondaryInk)
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
                .frame(minHeight: 110)
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
      .opacity(allQuestionsAnswered ? 1 : 0.48)
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .background(.ultraThinMaterial)
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
    VStack(alignment: .leading, spacing: 13) {
      Text(question.title)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(CaptroReceiptPalette.ink)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 10) {
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
        Text("Not great")
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
          Text("You earned \(money(cents: reward?.amountCents ?? 10))")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(CaptroReceiptPalette.reward)
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
      .padding(.horizontal, 20)
      .padding(.bottom, 18)
    }
  }

  private var feedbackQuestions: [CaptroFeedbackQuestion] {
    switch review?.category ?? .general {
    case .restaurantFood:
      return [
        .init(key: "cleanliness", title: "How clean was it?"),
        .init(key: "speed", title: "How fast was the service?"),
        .init(key: "quality", title: "How was the food quality?"),
        .init(key: "service", title: "How was the staff and service?"),
        .init(key: "overall", title: "Overall experience?"),
      ]
    case .productRetail:
      return [
        .init(key: "quality", title: "How was the product quality?"),
        .init(key: "value", title: "Was the item worth the price?"),
        .init(key: "organization", title: "How clean and organized was the place?"),
        .init(key: "speed", title: "How fast was checkout?"),
        .init(key: "overall", title: "Overall experience?"),
      ]
    case .grocery:
      return [
        .init(key: "freshness", title: "How fresh were the items?"),
        .init(key: "cleanliness", title: "How clean was the store?"),
        .init(key: "speed", title: "How fast was checkout?"),
        .init(key: "value", title: "Were prices reasonable?"),
        .init(key: "overall", title: "Overall experience?"),
      ]
    case .serviceBusiness:
      return [
        .init(key: "speed", title: "How fast was the service?"),
        .init(key: "professionalism", title: "How professional was the staff?"),
        .init(key: "satisfaction", title: "How satisfied were you?"),
        .init(key: "overall", title: "Overall experience?"),
      ]
    case .general:
      return [
        .init(key: "quality", title: "How was the purchase quality?"),
        .init(key: "value", title: "Was it worth the price?"),
        .init(key: "service", title: "How was the service?"),
        .init(key: "overall", title: "Overall experience?"),
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

  private func handleScannedPages(_ result: Result<[Data], Error>) {
    do {
      select(try CaptroLocalDocument.scanned(pages: result.get()))
    } catch {
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
    selectedDocument = document
    detectedType = nil
    review = nil
    reward = nil
    ratings = [:]
    note = ""
    reviewIdempotencyKey = "receipt-review:\(document.sha256Hex):\(UUID().uuidString)"
    feedbackIdempotencyKey = nil
    stage = .review
    isDetecting = true
    Task {
      let type = await CaptroDocumentTypeDetector.detect(document)
      guard selectedDocument?.id == document.id else { return }
      detectedType = type
      isDetecting = false
      guard type != .unsupported else { return }
      processReview(document, detectedType: type)
    }
  }

  private func processReview(_ document: CaptroLocalDocument, detectedType: CaptroDetectedDocumentType) {
    guard !isProcessingReview, let reviewIdempotencyKey else { return }
    isProcessingReview = true
    Task {
      defer { isProcessingReview = false }
      do {
        review = try await api.reviewCaptroReceipt(
          document,
          detectedType: detectedType,
          idempotencyKey: reviewIdempotencyKey
        )
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func continueToFeedback() {
    guard review?.rewardEligible == true else { return }
    feedbackIdempotencyKey = feedbackIdempotencyKey ?? "receipt-feedback:\(review?.receiptId ?? UUID().uuidString):\(UUID().uuidString)"
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
        errorMessage = error.localizedDescription
      }
    }
  }

  private func resetFlow() {
    stage = .capture
    selectedDocument = nil
    detectedType = nil
    review = nil
    reward = nil
    selectedPhoto = nil
    ratings = [:]
    note = ""
    reviewIdempotencyKey = nil
    feedbackIdempotencyKey = nil
    isDetecting = false
    isProcessingReview = false
    isSubmittingFeedback = false
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

  func captroReceiptSecondaryButton() -> some View {
    self
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(CaptroReceiptPalette.ink)
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(CaptroReceiptPalette.paper)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(CaptroReceiptPalette.line, lineWidth: 1))
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
