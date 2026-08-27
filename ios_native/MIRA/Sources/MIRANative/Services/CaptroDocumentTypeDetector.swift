import Foundation
import PDFKit
import UIKit
import Vision

enum CaptroDocumentTypeDetector {
  static func detect(_ document: CaptroLocalDocument) async -> CaptroDetectedDocumentType {
    let pages = document.pages
    let mediaType = document.mediaType
    return await Task.detached(priority: .userInitiated) {
      let images = previewImages(pages: pages, mediaType: mediaType)
      guard !images.isEmpty else { return .unsupported }

      var recognizedLines: [String] = []
      for image in images.prefix(3) {
        guard let cgImage = image.cgImage else { continue }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.008
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
          try handler.perform([request])
          recognizedLines.append(contentsOf: (request.results ?? []).compactMap {
            $0.topCandidates(1).first?.string
          })
        } catch {
          continue
        }
      }
      return classify(recognizedLines.joined(separator: "\n"))
    }.value
  }

  private static func previewImages(pages: [Data], mediaType: String) -> [UIImage] {
    if mediaType == "application/pdf", let data = pages.first, let pdf = PDFDocument(data: data) {
      return (0..<min(pdf.pageCount, 3)).compactMap { index in
        pdf.page(at: index)?.thumbnail(of: CGSize(width: 1_400, height: 1_800), for: .mediaBox)
      }
    }
    return pages.prefix(3).compactMap(UIImage.init(data:))
  }

  private static func classify(_ recognizedText: String) -> CaptroDetectedDocumentType {
    let text = recognizedText
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
    guard text.count >= 20 else { return .unsupported }

    let invoiceWeights: [(String, Int)] = [
      ("invoice", 4), ("invoice number", 3), ("invoice #", 3), ("bill to", 3),
      ("amount due", 3), ("due date", 3), ("payment terms", 3), ("purchase order", 2),
      ("po number", 2), ("unit price", 2),
    ]
    let receiptWeights: [(String, Int)] = [
      ("receipt", 4), ("cashier", 2), ("register", 2), ("change", 2),
      ("tender", 2), ("transaction", 2), ("thank you", 1), ("subtotal", 1),
      ("tax", 1), ("total", 1),
    ]

    let invoiceScore = score(text, weights: invoiceWeights)
    let receiptScore = score(text, weights: receiptWeights)
    if invoiceScore >= 5, invoiceScore >= receiptScore + 1 { return .invoice }
    if receiptScore >= 4, receiptScore > invoiceScore { return .receipt }
    return .unsupported
  }

  private static func score(_ text: String, weights: [(String, Int)]) -> Int {
    weights.reduce(0) { total, entry in
      total + (text.contains(entry.0) ? entry.1 : 0)
    }
  }
}
