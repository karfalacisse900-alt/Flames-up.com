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
    XCTAssertEqual(AuraExpectedDevnet.chainId, "aura-devnet-pow-v2")
    XCTAssertEqual(AuraExpectedDevnet.chainIdHash.count, 64)
    XCTAssertEqual(AuraExpectedDevnet.genesisHash.count, 64)
  }
}
