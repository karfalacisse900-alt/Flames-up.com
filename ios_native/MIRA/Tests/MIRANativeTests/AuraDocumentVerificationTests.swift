import Foundation
import XCTest
@testable import MIRANative

final class AuraDocumentVerificationTests: XCTestCase {
  func testProviderResultCannotBeMistakenForProofOrBlockchainConfirmation() throws {
    let json = #"""
    {
      "provider":"Veryfi",
      "providerDocumentId":"provider-123",
      "submittedType":"receipt",
      "providerDocumentType":"receipt",
      "isDocument":true,
      "verificationLevel":2,
      "verificationLabel":"Document Verified",
      "documentVerified":true,
      "transactionCorroborated":false,
      "merchantSigned":false,
      "proofIssued":false,
      "blockchainSubmitted":false,
      "independentPurchaseConfirmed":false,
      "merchant":{"name":"Example Store","address":null,"phone":null,"storeNumber":"7"},
      "date":"2026-08-24",
      "time":null,
      "currency":"USD",
      "subtotal":"10.00",
      "tax":"0.80",
      "discount":null,
      "total":"10.80",
      "invoiceNumber":null,
      "dueDate":null,
      "receiptNumber":"R-1",
      "duplicate":false,
      "fraud":{"decision":"green","score":"0.01","digitalTampering":false,"aiGenerated":false,"screenshot":false,"invalidQr":false,"vendorLayoutMismatch":false,"notADocument":false},
      "lineItems":[],
      "rawResponseSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "privacy":{"storedByAura":false,"providerAutoDeleteRequested":true}
    }
    """#
    let result = try JSONDecoder().decode(
      AuraDocumentVerificationResult.self,
      from: Data(json.utf8)
    )
    XCTAssertTrue(result.documentVerified)
    XCTAssertFalse(result.transactionCorroborated)
    XCTAssertFalse(result.merchantSigned)
    XCTAssertFalse(result.proofIssued)
    XCTAssertFalse(result.blockchainSubmitted)
    XCTAssertFalse(result.independentPurchaseConfirmed)
    XCTAssertFalse(result.privacy.storedByAura)
  }
}
