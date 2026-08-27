import XCTest
@testable import MIRANative

final class AuraWalletGatewayTests: XCTestCase {
  func testAmountCodecUsesExactAtomicUnits() throws {
    XCTAssertEqual(try AuraAmountCodec.atoms(fromAUR: "1"), 100_000_000)
    XCTAssertEqual(try AuraAmountCodec.atoms(fromAUR: "1.00000001"), 100_000_001)
    XCTAssertEqual(try AuraAmountCodec.atoms(fromAUR: "0.1"), 10_000_000)
    XCTAssertEqual(AuraAmountCodec.aur(fromAtoms: "100000001"), "1.00000001")
    XCTAssertEqual(AuraAmountCodec.aur(fromAtoms: "800000000"), "8")
  }

  func testAmountCodecRejectsRoundingAndOverflow() {
    XCTAssertThrowsError(try AuraAmountCodec.atoms(fromAUR: "0"))
    XCTAssertThrowsError(try AuraAmountCodec.atoms(fromAUR: "1.000000001"))
    XCTAssertThrowsError(try AuraAmountCodec.atoms(fromAUR: "-1"))
    XCTAssertThrowsError(try AuraAmountCodec.atoms(fromAUR: "184467440738"))
  }

  func testExpectedDevnetIdentityIsFrozenInTheLightClient() {
    XCTAssertEqual(AuraExpectedDevnet.protocolVersion, "2")
    XCTAssertEqual(AuraExpectedDevnet.network, "devnet")
    XCTAssertEqual(AuraExpectedDevnet.chainId, "aura-devnet-pow-v2-proof1")
    XCTAssertEqual(
      AuraExpectedDevnet.chainIdHash,
      "f2d47ba05f05c086e8e5507ef7be2fa764effaefacab13bd613543e4163575b9"
    )
    XCTAssertEqual(
      AuraExpectedDevnet.genesisHash,
      "75b26958bc3414b7f32370179c077710b7f35e1c05df21d0f8038d363ecc8c24"
    )
    XCTAssertEqual(AuraExpectedDevnet.chainIdHash.count, 64)
    XCTAssertEqual(AuraExpectedDevnet.genesisHash.count, 64)
  }

  func testBalanceSnapshotKeepsPendingIncomingNonSpendable() throws {
    let data = Data(
      """
      {
        "address": "daura1receiver",
        "availableAtoms": "10000000000",
        "confirmedAtoms": "10000000000",
        "lockedAtoms": "0",
        "pendingIncomingAtoms": "1000000000",
        "pendingOutgoingAtoms": "0",
        "pendingFeeAtoms": "0",
        "spendableAtoms": "10000000000",
        "totalVisibleAtoms": "11000000000"
      }
      """.utf8
    )

    let balance = try JSONDecoder().decode(AuraGatewayBalance.self, from: data)

    XCTAssertEqual(balance.confirmedAtoms, "10000000000")
    XCTAssertEqual(balance.pendingIncomingAtoms, "1000000000")
    XCTAssertEqual(balance.spendableAtoms, "10000000000")
    XCTAssertEqual(balance.totalVisibleAtoms, "11000000000")
  }

  func testDuplicateLifecycleEventsDecodeToTheSameNotification() throws {
    let data = Data(
      """
      {
        "type": "transaction_in_mempool",
        "sequence": "42",
        "transactionId": "aabbcc",
        "sender": "daura1sender",
        "recipient": "daura1receiver",
        "amountAtoms": "1000000000",
        "feeAtoms": "1000",
        "blockId": null,
        "blockHeight": null,
        "confirmations": "0",
        "tipHash": null,
        "tipHeight": null,
        "reason": null
      }
      """.utf8
    )

    let first = try JSONDecoder().decode(AuraGatewayLifecycleEvent.self, from: data)
    let duplicate = try JSONDecoder().decode(AuraGatewayLifecycleEvent.self, from: data)

    XCTAssertEqual(first, duplicate)
    XCTAssertEqual(first.type, "transaction_in_mempool")
    XCTAssertEqual(first.sequence, "42")
  }
}
