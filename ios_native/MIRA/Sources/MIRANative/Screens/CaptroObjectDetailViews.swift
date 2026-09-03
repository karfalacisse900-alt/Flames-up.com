import SwiftUI
import CoreImage.CIFilterBuiltins
import PDFKit
import UIKit

struct CaptroPDFOriginal: UIViewRepresentable {
  let data: Data

  func makeUIView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    view.backgroundColor = .white
    view.document = PDFDocument(data: data)
    return view
  }

  func updateUIView(_ view: PDFView, context: Context) {}
}

struct CaptroEventTicketSection: View {
  let ticket: CaptroOwnedTicket
  let postID: String
  let api: MIRAAPIClient

  var body: some View {
    VStack(spacing: 14) {
      CaptroTicketCode(ticket: ticket)
      if let tier = ticket.tier {
        Text(tier.uppercased())
          .font(.system(size: 12, weight: .bold))
          .padding(.horizontal, 12).padding(.vertical, 6)
          .background(CaptroDetailStyle.accent.opacity(0.18))
      }
      HStack(spacing: 24) {
        CaptroObjectField(title: "Section", value: ticket.section)
        CaptroObjectField(title: "Seat", value: ticket.seat)
      }
      if ticket.downloadable { CaptroTicketDownload(postID: postID, title: "View Ticket", api: api) }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
    .privacySensitive()
    .overlay(alignment: .bottom) { CaptroTicketPerforation() }
  }
}

struct CaptroTravelDetailSection: View {
  let post: MIRAPost
  let ticket: CaptroOwnedTicket?
  let api: MIRAAPIClient

  private var travel: CaptroTravelDetails? { post.detail?.travel }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top, spacing: 12) {
        Text(travel?.operator ?? post.titleText)
          .font(.system(size: 24, weight: .bold))
          .frame(maxWidth: .infinity, alignment: .leading)
        if let price = travel?.price {
          Text([travel?.currency, price].compactMap { $0 }.joined(separator: " "))
            .font(.system(size: 16, weight: .semibold))
        }
      }
      CaptroTicketPerforation()
      HStack(alignment: .top, spacing: 12) {
        routeStop(code: travel?.originCode, city: travel?.originCity)
        VStack(spacing: 6) {
          Image(systemName: "arrow.right").font(.system(size: 18))
          if let duration = travel?.duration { Text(duration).font(.system(size: 11, weight: .semibold)) }
        }.padding(.top, 6)
        routeStop(code: travel?.destinationCode, city: travel?.destinationCity)
      }
      if let ticket {
        VStack(alignment: .leading, spacing: 4) {
          CaptroObjectField(title: "Passenger", value: ticket.passengerName)
          if let email = ticket.passengerEmail {
            Text(email).font(.system(size: 13)).foregroundStyle(CaptroDetailStyle.secondary)
          }
        }.privacySensitive()
      }
      LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 20) {
        CaptroObjectField(title: "Service", value: ticket?.serviceNumber ?? travel?.serviceNumber)
        CaptroObjectField(title: "Class", value: ticket?.travelClass ?? travel?.travelClass)
        CaptroObjectField(title: "Departure", value: ticket?.departure ?? travel?.departure)
        CaptroObjectField(title: "Arrival", value: ticket?.arrival ?? travel?.arrival)
        CaptroObjectField(title: "Terminal", value: ticket?.terminal)
        CaptroObjectField(title: "Gate", value: ticket?.gate)
        CaptroObjectField(title: "Seat", value: ticket?.seat)
      }
      if let ticket {
        CaptroTicketPerforation()
        CaptroTicketCode(ticket: ticket).frame(maxWidth: .infinity)
        if ticket.downloadable { CaptroTicketDownload(postID: post.id, title: "Download Ticket", api: api) }
      }
      if !post.detailCaption.isEmpty {
        Text(post.detailCaption).font(.system(size: 15)).lineSpacing(4)
      }
      CaptroDetailCreatorRow(post: post, api: api)
    }
    .padding(20)
    .background(Color.white)
    .foregroundStyle(CaptroDetailStyle.ink)
  }

  private func routeStop(code: String?, city: String?) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      if let code { Text(code).font(.system(size: 28, weight: .bold)).minimumScaleFactor(0.7) }
      if let city { Text(city).font(.system(size: 13)).foregroundStyle(CaptroDetailStyle.secondary) }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct CaptroDocumentFacts: View {
  let review: CaptroReceiptReview
  private var isInvoice: Bool { review.documentType == "invoice" }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(isInvoice ? "INVOICE" : "RECEIPT")
        .font(.system(size: 24, weight: .bold)).accessibilityAddTraits(.isHeader)
      if isInvoice {
        CaptroObjectField(title: "Invoice #", value: review.documentNumber)
        CaptroObjectField(title: "From", value: review.merchantName)
        CaptroObjectField(title: "Bill To", value: review.customer?.name)
        CaptroObjectField(title: "Billing address", value: review.customer?.address)
        HStack(alignment: .top, spacing: 24) {
          CaptroObjectField(title: "Issued", value: review.purchaseDate)
          CaptroObjectField(title: "Due", value: review.dueDate)
        }
      } else {
        CaptroObjectField(title: "Merchant", value: review.merchantName)
        HStack(alignment: .top, spacing: 24) {
          CaptroObjectField(title: "Date", value: review.purchaseDate)
          CaptroObjectField(title: "Time", value: review.purchaseTime)
        }
        CaptroObjectField(title: "Receipt #", value: review.documentNumber)
      }
      CaptroObjectField(title: "Location", value: review.business?.address?.original)
      if !review.items.isEmpty {
        Divider()
        Text("Items · \(review.items.count)").font(.system(size: 13, weight: .semibold))
        ForEach(Array(review.items.enumerated()), id: \.offset) { _, item in
          HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              if let description = item.description { Text(description).font(.system(size: 15)) }
              if let quantity = item.quantity {
                Text([quantity, item.unitPrice.map { "× \($0)" }].compactMap { $0 }.joined(separator: " "))
                  .font(.system(size: 12)).foregroundStyle(CaptroDetailStyle.secondary)
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let amount = item.total { Text(amount).font(.system(size: 15)).monospacedDigit() }
          }
        }
      }
      Divider()
      amount("Subtotal", review.subtotal)
      amount("Tax", review.tax)
      amount("Fees", review.fees)
      amount("Discount", review.discount)
      amount("Total", review.total, strong: true)
      CaptroObjectField(title: "Payment terms", value: review.paymentTerms)
      Divider()
      CaptroDocumentVerification(review: review)
    }
    .foregroundStyle(CaptroDetailStyle.ink)
    .privacySensitive()
  }

  @ViewBuilder private func amount(_ title: String, _ value: String?, strong: Bool = false) -> some View {
    if let value {
      HStack {
        Text(title)
        Spacer(minLength: 12)
        Text([review.currency, value].compactMap { $0 }.joined(separator: " ")).monospacedDigit()
      }.font(.system(size: strong ? 19 : 14, weight: strong ? .bold : .regular))
    }
  }
}

struct CaptroDocumentVerification: View {
  let review: CaptroReceiptReview

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("VERIFICATION").font(.system(size: 12, weight: .bold)).accessibilityAddTraits(.isHeader)
      Text(review.status == "processing" ? "Processing" : review.verdict == "Verified" && !review.duplicate ? "Verified" : "Unable to Verify")
        .font(.system(size: 18, weight: .semibold))
      ForEach(review.checks ?? []) { check in
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: check.status == "passed" ? "checkmark.circle" : "minus.circle")
            .frame(width: 18)
          VStack(alignment: .leading, spacing: 3) {
            Text(checkTitle(check.key)).font(.system(size: 13, weight: .medium))
            Text(check.detail).font(.system(size: 12)).foregroundStyle(CaptroDetailStyle.secondary)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(check.status == "passed" ? "Passed" : "Not confirmed")
      }
      CaptroObjectField(title: "Verification ID", value: review.verificationId)
    }
  }

  private func checkTitle(_ key: String) -> String {
    switch key {
    case "document_processed": return "Document processed"
    case "document_structure": return "Required fields present"
    case "merchant_extracted": return "Merchant data present"
    case "amount_extracted": return "Amount extracted"
    case "provider_document_signal": return "Provider document check"
    case "date_validity": return "Document date"
    case "total_arithmetic": return "Total consistency"
    case "line_item_arithmetic": return "Item consistency"
    case "duplicate_check": return "Duplicate check"
    case "business_address": return "Address extracted"
    case "document_identifier": return "Document number extracted"
    case "barcode_or_qr": return "Document code extracted"
    default: return "Document check"
    }
  }
}

private struct CaptroObjectField: View {
  let title: String
  let value: String?
  var body: some View {
    if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 12)).foregroundStyle(CaptroDetailStyle.secondary)
        Text(value).font(.system(size: 15, weight: .medium)).textSelection(.enabled)
      }.fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct CaptroTicketPerforation: View {
  var body: some View {
    Rectangle().fill(CaptroDetailStyle.divider).frame(height: 1)
  }
}

private struct CaptroTicketCode: View {
  let ticket: CaptroOwnedTicket
  private var codeImage: UIImage? {
    guard let code = ticket.code, let format = ticket.codeFormat else { return nil }
    let filter: CIFilter
    if format == "qr" {
      let qr = CIFilter.qrCodeGenerator()
      qr.message = Data(code.utf8)
      qr.correctionLevel = "M"
      filter = qr
    } else if format == "code128", let data = code.data(using: .ascii) {
      let barcode = CIFilter.code128BarcodeGenerator()
      barcode.message = data
      filter = barcode
    } else { return nil }
    guard let output = filter.outputImage,
          let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
    return UIImage(cgImage: image)
  }
  var body: some View {
    if let image = codeImage {
      Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        .frame(maxWidth: ticket.codeFormat == "qr" ? 148 : 320)
        .frame(height: ticket.codeFormat == "qr" ? 148 : 76)
        .padding(12).background(Color.white)
        .accessibilityLabel("Your ticket code")
        .privacySensitive()
    }
  }
}

private struct CaptroTicketDownload: View {
  let postID: String
  let title: String
  let api: MIRAAPIClient
  @Environment(\.openURL) private var openURL
  @State private var loading = false
  @State private var error: String?
  var body: some View {
    VStack(spacing: 8) {
      Button {
        Task {
          loading = true
          defer { loading = false }
          do {
            let link: CaptroPrivateDocumentLink = try await api.get("/posts/\(postID)/ticket")
            openURL(link.signedUrl)
          } catch { self.error = "Couldn't open your ticket. Try again." }
        }
      } label: {
        Label(title, systemImage: loading ? "hourglass" : "arrow.down.to.line")
          .font(.system(size: 14, weight: .semibold))
          .frame(maxWidth: .infinity, minHeight: 44)
          .overlay(Rectangle().stroke(CaptroDetailStyle.divider, lineWidth: 1))
      }.buttonStyle(.plain).disabled(loading)
      if let error { Text(error).font(.system(size: 12)) }
    }
  }
}

struct CaptroPrivateReceiptOriginal: View {
  let receiptID: String
  let api: MIRAAPIClient
  @State private var document: CaptroLocalDocument?
  @State private var error: String?
  @State private var attempt = 0
  @State private var showingDocument = false

  var body: some View {
    VStack(spacing: 8) {
      if let image = document?.firstPageImage {
        Button { showingDocument = true } label: {
          Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
        }.buttonStyle(.plain).accessibilityLabel("View original document")
      } else if let error {
        Button { attempt += 1 } label: { Label(error, systemImage: "arrow.clockwise").font(.system(size: 13)) }.padding(20)
      } else { ProgressView().frame(maxWidth: .infinity).padding(30) }
    }
    .privacySensitive()
    .sheet(isPresented: $showingDocument) {
      if let document { CaptroLocalDocumentViewer(document: document) }
    }
    .task(id: attempt) {
      error = nil
      do {
        let link = try await api.captroReceiptOriginalLink(id: receiptID)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: link.signedUrl)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CaptroLocalDocumentError.inaccessible }
        document = try CaptroLocalDocument.privateDownload(data: data)
      } catch { self.error = "Couldn't load the original. Try again." }
    }
  }
}
