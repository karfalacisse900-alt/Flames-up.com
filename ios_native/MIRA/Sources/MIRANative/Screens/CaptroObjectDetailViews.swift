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
  let post: MIRAPost
  let ticket: CaptroOwnedTicket?
  let api: MIRAAPIClient

  private var event: CaptroEventDetails? { post.detail?.event }
  private var ticketLabel: String {
    [ticket?.tier, ticket?.section.map { "Section \($0)" }, ticket?.seat.map { "Seat \($0)" }]
      .compactMap { $0 }.joined(separator: " · ")
  }

  var body: some View {
    VStack(spacing: 18) {
      if let ticket { CaptroTicketCode(ticket: ticket) }
      if !ticketLabel.isEmpty {
        Label(ticketLabel, systemImage: "ticket.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.white)
          .padding(.horizontal, 12).padding(.vertical, 7)
          .background(CaptroDetailStyle.ink)
          .clipShape(Capsule())
          .privacySensitive()
      }
      Text(post.captroCleanTitle ?? "Meetup")
        .font(.system(size: 24, weight: .bold))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      VStack(spacing: 11) {
        ticketFact(event?.timeRange, icon: "clock")
        ticketFact(event?.calendarDate, icon: "calendar")
        let venue = [event?.venueName ?? post.placeDisplayName, event?.address, event?.city]
          .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !venue.isEmpty { ticketFact(venue, icon: "mappin.and.ellipse") }
        if let price = event?.priceLabel {
          Text(price).font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(CaptroDetailStyle.accent.opacity(0.12))
        }
        if let map = post.detailMapURL {
          Link(destination: map) {
            Label("View on map", systemImage: "arrow.up.right")
              .font(.system(size: 13, weight: .medium)).frame(minHeight: 36)
          }.foregroundStyle(CaptroDetailStyle.accent)
        }
      }
      if ticket?.downloadable == true { CaptroTicketDownload(postID: post.id, title: "View Ticket", api: api) }
      CaptroTicketPerforation().padding(.top, 8)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 24)
    .background(Color.white)
  }

  @ViewBuilder private func ticketFact(_ value: String?, icon: String) -> some View {
    if let value, !value.isEmpty {
      Label(value, systemImage: icon)
        .font(.system(size: 14))
        .foregroundStyle(CaptroDetailStyle.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct CaptroTravelDetailSection: View {
  let post: MIRAPost
  let ticket: CaptroOwnedTicket?
  let api: MIRAAPIClient
  @State private var headerHeight: CGFloat = 76

  private var travel: CaptroTravelDetails? { post.detail?.travel }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      boardingPass
      if !post.detailCaption.isEmpty {
        Text(post.detailCaption).font(.system(size: 15)).lineSpacing(4)
      }
      CaptroDetailCreatorRow(post: post, api: api)
    }
    .padding(16)
    .foregroundStyle(CaptroDetailStyle.ink)
  }

  private var boardingPass: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "ticket")
          .font(.system(size: 18))
          .frame(width: 36, height: 36)
          .background(CaptroDetailStyle.accent.opacity(0.14))
          .clipShape(Circle())
        Text(travel?.operator ?? post.titleText)
          .font(.system(size: 20, weight: .bold))
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let price = travel?.price {
          Text([travel?.currency, price].compactMap { $0 }.joined(separator: " "))
            .font(.system(size: 16, weight: .semibold))
        }
      }.padding(20)
        .background(GeometryReader { geometry in
          Color.clear.preference(key: CaptroTicketHeaderHeight.self, value: geometry.size.height)
        })
      CaptroTicketPerforation().padding(.horizontal, 12)
      VStack(alignment: .leading, spacing: 24) {
        if travel?.originCode != nil || travel?.originCity != nil || travel?.destinationCode != nil || travel?.destinationCity != nil {
          HStack(alignment: .top, spacing: 8) {
            routeStop(code: travel?.originCode, city: travel?.originCity)
            VStack(spacing: 6) {
              Image(systemName: "arrow.right").font(.system(size: 17))
              if let duration = travel?.duration {
                Text(duration).font(.system(size: 11, weight: .semibold)).multilineTextAlignment(.center)
              }
            }.frame(maxWidth: .infinity).padding(.top, 6)
            routeStop(code: travel?.destinationCode, city: travel?.destinationCity, alignment: .trailing)
          }
        }
        if let ticket {
          HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
              CaptroObjectField(title: "Passenger", value: ticket.passengerName)
              if let email = ticket.passengerEmail {
                Text(email).font(.system(size: 12)).foregroundStyle(CaptroDetailStyle.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
            CaptroObjectField(title: "Seat", value: ticket.seat)
          }.privacySensitive()
        }
        pairedFields("Service", ticket?.serviceNumber ?? travel?.serviceNumber, "Class", ticket?.travelClass ?? travel?.travelClass)
        pairedFields("Departure", ticket?.departure ?? travel?.departure, "Arrival", ticket?.arrival ?? travel?.arrival)
        pairedFields("Terminal", ticket?.terminal, "Gate", ticket?.gate)
      }
      .padding(20)
      if let ticket {
        CaptroTicketCode(ticket: ticket)
          .frame(maxWidth: .infinity).padding(.vertical, 12)
          .background(CaptroDetailStyle.accent.opacity(0.06))
        if ticket.downloadable {
          CaptroTicketDownload(postID: post.id, title: "Download Ticket", api: api).padding(16)
        }
      }
    }
    .background(Color.white)
    .clipShape(CaptroBoardingPassShape(notchY: headerHeight))
    .overlay(CaptroBoardingPassShape(notchY: headerHeight).stroke(CaptroDetailStyle.divider, lineWidth: 1))
    .onPreferenceChange(CaptroTicketHeaderHeight.self) { headerHeight = $0 }
  }

  @ViewBuilder private func pairedFields(_ left: String, _ leftValue: String?, _ right: String, _ rightValue: String?) -> some View {
    if leftValue != nil || rightValue != nil {
      HStack(alignment: .top, spacing: 20) {
        CaptroObjectField(title: left, value: leftValue).frame(maxWidth: .infinity, alignment: .leading)
        CaptroObjectField(title: right, value: rightValue).frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
  }

  private func routeStop(code: String?, city: String?, alignment: HorizontalAlignment = .leading) -> some View {
    VStack(alignment: alignment, spacing: 5) {
      if let code { Text(code).font(.system(size: 28, weight: .bold)).lineLimit(1).minimumScaleFactor(0.65) }
      if let city { Text(city).font(.system(size: 13)).foregroundStyle(CaptroDetailStyle.secondary).fixedSize(horizontal: false, vertical: true) }
    }.frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
  }
}

private struct CaptroTicketHeaderHeight: PreferenceKey {
  static var defaultValue: CGFloat = 76
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct CaptroBoardingPassShape: Shape {
  var notchY: CGFloat
  func path(in rect: CGRect) -> Path {
    let w = rect.width, h = rect.height
    let y = min(max(16, notchY), max(16, h - 16))
    var path = Path()
    path.move(to: CGPoint(x: 8, y: 0))
    path.addLine(to: CGPoint(x: w - 8, y: 0))
    path.addQuadCurve(to: CGPoint(x: w, y: 8), control: CGPoint(x: w, y: 0))
    path.addLine(to: CGPoint(x: w, y: y - 8))
    path.addCurve(to: CGPoint(x: w, y: y + 8), control1: CGPoint(x: w - 12, y: y - 8), control2: CGPoint(x: w - 12, y: y + 8))
    path.addLine(to: CGPoint(x: w, y: h - 8))
    path.addQuadCurve(to: CGPoint(x: w - 8, y: h), control: CGPoint(x: w, y: h))
    path.addLine(to: CGPoint(x: 8, y: h))
    path.addQuadCurve(to: CGPoint(x: 0, y: h - 8), control: CGPoint(x: 0, y: h))
    path.addLine(to: CGPoint(x: 0, y: y + 8))
    path.addCurve(to: CGPoint(x: 0, y: y - 8), control1: CGPoint(x: 12, y: y + 8), control2: CGPoint(x: 12, y: y - 8))
    path.addLine(to: CGPoint(x: 0, y: 8))
    path.addQuadCurve(to: CGPoint(x: 8, y: 0), control: .zero)
    path.closeSubpath()
    return path
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
    GeometryReader { geometry in
      Path { path in
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
      }.stroke(CaptroDetailStyle.divider, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
    }.frame(height: 1)
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
