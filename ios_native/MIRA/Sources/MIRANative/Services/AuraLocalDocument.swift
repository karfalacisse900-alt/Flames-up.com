import CryptoKit
import Foundation
import PDFKit
import UIKit

enum AuraLocalDocumentError: Error, LocalizedError {
  case inaccessible
  case empty
  case tooLarge
  case unsupported
  case corrupt

  var errorDescription: String? {
    switch self {
    case .inaccessible: return "Aura could not securely read that file."
    case .empty: return "The selected document is empty."
    case .tooLarge: return "Documents must be 12 MiB or smaller."
    case .unsupported: return "Choose a JPG, PNG, HEIC/HEIF, or PDF document."
    case .corrupt: return "The selected document could not be decoded safely."
    }
  }
}

enum AuraLocalDocumentSource: String {
  case camera = "Document Scanner"
  case fileImport = "Files Import"
  case photoLibrary = "Photo Library"
}

/// In-memory receipt/invoice selected for the next verification step. Sensitive bytes are not
/// persisted by this type and disappear when the selection is cleared or the view is released.
struct AuraLocalDocument: Identifiable {
  static let maximumBytes = 12 * 1024 * 1024

  let id = UUID()
  let kind: AuraScanDocumentKind
  let source: AuraLocalDocumentSource
  let filename: String
  let mediaType: String
  let pages: [Data]
  let byteCount: Int
  let sha256Hex: String

  var firstPageImage: UIImage? {
    guard mediaType != "application/pdf", let first = pages.first else { return nil }
    return UIImage(data: first)
  }

  static func scanned(kind: AuraScanDocumentKind, pages: [Data]) throws -> Self {
    try make(
      kind: kind,
      source: .camera,
      filename: kind == .receipt ? "Scanned Receipt.jpg" : "Scanned Invoice.jpg",
      mediaType: "image/jpeg",
      pages: pages
    )
  }

  static func imported(kind: AuraScanDocumentKind, url: URL) throws -> Self {
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed { url.stopAccessingSecurityScopedResource() }
    }

    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values?.isRegularFile != false else { throw AuraLocalDocumentError.inaccessible }
    guard let size = values?.fileSize, size > 0 else { throw AuraLocalDocumentError.empty }
    guard size <= maximumBytes else { throw AuraLocalDocumentError.tooLarge }

    let data: Data
    do {
      data = try Data(contentsOf: url, options: [.mappedIfSafe])
    } catch {
      throw AuraLocalDocumentError.inaccessible
    }
    let mediaType = try detectAndValidate(data)
    return try make(
      kind: kind,
      source: .fileImport,
      filename: url.lastPathComponent,
      mediaType: mediaType,
      pages: [data]
    )
  }

  static func photoImported(kind: AuraScanDocumentKind, data: Data) throws -> Self {
    guard !data.isEmpty else { throw AuraLocalDocumentError.empty }
    guard data.count <= maximumBytes else { throw AuraLocalDocumentError.tooLarge }
    let mediaType = try detectAndValidate(data)
    guard mediaType != "application/pdf" else { throw AuraLocalDocumentError.unsupported }
    return try make(
      kind: kind,
      source: .photoLibrary,
      filename: kind == .receipt ? "Imported Receipt Image" : "Imported Invoice Image",
      mediaType: mediaType,
      pages: [data]
    )
  }

  private static func make(
    kind: AuraScanDocumentKind,
    source: AuraLocalDocumentSource,
    filename: String,
    mediaType: String,
    pages: [Data]
  ) throws -> Self {
    guard !pages.isEmpty, pages.allSatisfy({ !$0.isEmpty }) else {
      throw AuraLocalDocumentError.empty
    }
    let byteCount = try pages.reduce(0) { partial, page in
      let total = partial.addingReportingOverflow(page.count)
      guard !total.overflow else { throw AuraLocalDocumentError.tooLarge }
      return total.partialValue
    }
    guard byteCount <= maximumBytes else { throw AuraLocalDocumentError.tooLarge }

    if mediaType != "application/pdf" {
      guard pages.allSatisfy({ UIImage(data: $0) != nil }) else {
        throw AuraLocalDocumentError.corrupt
      }
    }

    return Self(
      kind: kind,
      source: source,
      filename: filename,
      mediaType: mediaType,
      pages: pages,
      byteCount: byteCount,
      sha256Hex: hash(pages: pages)
    )
  }

  private static func detectAndValidate(_ data: Data) throws -> String {
    if data.starts(with: Data("%PDF-".utf8)) {
      guard PDFDocument(data: data) != nil else { throw AuraLocalDocumentError.corrupt }
      return "application/pdf"
    }
    if data.starts(with: [0xFF, 0xD8, 0xFF]) {
      guard UIImage(data: data) != nil else { throw AuraLocalDocumentError.corrupt }
      return "image/jpeg"
    }
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
      guard UIImage(data: data) != nil else { throw AuraLocalDocumentError.corrupt }
      return "image/png"
    }
    if data.count >= 12,
       data[4..<8].elementsEqual(Data("ftyp".utf8)),
       ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(
         String(decoding: data[8..<12], as: UTF8.self)
       ) {
      guard UIImage(data: data) != nil else { throw AuraLocalDocumentError.corrupt }
      return "image/heic"
    }
    throw AuraLocalDocumentError.unsupported
  }

  private static func hash(pages: [Data]) -> String {
    var hasher = SHA256()
    hasher.update(data: Data("AURA_LOCAL_DOCUMENT_V1".utf8))
    for page in pages {
      var length = UInt64(page.count).bigEndian
      withUnsafeBytes(of: &length) { hasher.update(data: Data($0)) }
      hasher.update(data: page)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
