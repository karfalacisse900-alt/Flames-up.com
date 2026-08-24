import PDFKit
import UIKit
import XCTest
@testable import MIRANative

final class AuraLocalDocumentTests: XCTestCase {
  func testPNGImportIsBoundedDecodedAndHasAStableLocalHash() throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 48)).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
      UIColor.black.setFill()
      context.fill(CGRect(x: 4, y: 4, width: 24, height: 4))
    }
    let data = try XCTUnwrap(image.pngData())
    let url = temporaryURL(extension: "png")
    defer { try? FileManager.default.removeItem(at: url) }
    try data.write(to: url)

    let first = try AuraLocalDocument.imported(kind: .receipt, url: url)
    let second = try AuraLocalDocument.imported(kind: .receipt, url: url)

    XCTAssertEqual(first.mediaType, "image/png")
    XCTAssertEqual(first.byteCount, data.count)
    XCTAssertEqual(first.sha256Hex, second.sha256Hex)
    XCTAssertEqual(first.sha256Hex.count, 64)
    XCTAssertNotNil(first.firstPageImage)
  }

  func testPDFImportIsRecognizedWithoutCallingItVerified() throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
    }
    let pdf = PDFDocument()
    pdf.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
    let data = try XCTUnwrap(pdf.dataRepresentation())
    let url = temporaryURL(extension: "pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    try data.write(to: url)

    let document = try AuraLocalDocument.imported(kind: .invoice, url: url)
    XCTAssertEqual(document.kind, .invoice)
    XCTAssertEqual(document.mediaType, "application/pdf")
    XCTAssertNil(document.firstPageImage)
  }

  func testUnsupportedAndOversizedFilesAreRejectedBeforeVerification() throws {
    let textURL = temporaryURL(extension: "txt")
    defer { try? FileManager.default.removeItem(at: textURL) }
    try Data("not a document".utf8).write(to: textURL)
    XCTAssertThrowsError(try AuraLocalDocument.imported(kind: .receipt, url: textURL))

    let largeURL = temporaryURL(extension: "png")
    defer { try? FileManager.default.removeItem(at: largeURL) }
    try Data(count: AuraLocalDocument.maximumBytes + 1).write(to: largeURL)
    XCTAssertThrowsError(try AuraLocalDocument.imported(kind: .receipt, url: largeURL))
  }

  func testMultiPageScanBecomesOneInMemoryPDFUpload() throws {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60))
    let first = try XCTUnwrap(renderer.image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
    }.jpegData(compressionQuality: 0.9))
    let second = try XCTUnwrap(renderer.image { context in
      UIColor.lightGray.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
    }.jpegData(compressionQuality: 0.9))

    let document = try AuraLocalDocument.scanned(kind: .invoice, pages: [first, second])
    let upload = try document.verificationUpload()
    let pdf = try XCTUnwrap(PDFDocument(data: upload.data))

    XCTAssertEqual(upload.mediaType, "application/pdf")
    XCTAssertTrue(upload.filename.hasSuffix(".pdf"))
    XCTAssertEqual(pdf.pageCount, 2)
    XCTAssertLessThanOrEqual(upload.data.count, AuraLocalDocument.maximumBytes)
  }

  private func temporaryURL(extension pathExtension: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(pathExtension)
  }
}
