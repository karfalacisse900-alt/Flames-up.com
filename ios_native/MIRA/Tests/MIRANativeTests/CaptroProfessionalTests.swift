import XCTest
@testable import MIRANative
final class CaptroProfessionalTests: XCTestCase {
  func testSeparateRolesAndOptionalWebsite() throws {
    let creator = CaptroProfessionalData(displayName: "Sample", category: "musician", description: "Independent musician")
    XCTAssertTrue(creator.valid(for: .creator)); XCTAssertFalse(creator.valid(for: .business))
    var bad = creator; bad.links = ["http://example.com"]; XCTAssertFalse(bad.valid(for: .creator))
    bad.links = ["https://user:secret@example.com"]; XCTAssertFalse(bad.valid(for: .creator))
    var business = CaptroProfessionalData(displayName: "Coffee", category: "coffee_bakery", description: "Coffee", pickup: true)
    XCTAssertFalse(business.valid(for: .business)); business.area = "Brooklyn"; XCTAssertTrue(business.valid(for: .business))
  }
  func testOldUserAndNewStateDecodeWithoutAssumingApproval() throws {
    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
    XCTAssertNil(try decoder.decode(MIRAUser.self, from: Data(#"{"id":"old-user","username":"old_user"}"#.utf8)).professional)
    let state = try decoder.decode(CaptroProfessionalState.self, from: Data(#"{"applications":[{"role":"creator","status":"under_review","version":1,"public_data":{"displayName":"Artist","category":"musician","description":"Music","links":[],"area":"","pickup":false,"portfolioPostIds":[]}}],"roles":[]}"#.utf8))
    XCTAssertEqual(state.applications.first?.statusLabel, "Under review"); XCTAssertTrue(state.roles.isEmpty)
  }
}
