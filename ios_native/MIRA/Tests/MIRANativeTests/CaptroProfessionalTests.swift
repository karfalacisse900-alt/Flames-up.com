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
  func testPortfolioNeverIntroducesLegacyTextOrDuplicatesIntoMoments() throws {
    let decoder = JSONDecoder()
    let legacy = try decoder.decode(MIRAPost.self, from: Data(#"{"id":"text","postType":"general","caption":"Old text"}"#.utf8))
    let photo = try decoder.decode(MIRAPost.self, from: Data(#"{"id":"photo","postType":"general","image":"https://example.com/photo.jpg"}"#.utf8))
    let event = try decoder.decode(MIRAPost.self, from: Data(#"{"id":"event","postType":"event"}"#.utf8))
    var user = try decoder.decode(MIRAUser.self, from: Data(#"{"id":"artist"}"#.utf8))
    user.professional = [CaptroProfessionalPublicRole(role:"creator",displayName:"Artist",category:"artist",description:"Art",links:[],area:"",pickup:false,portfolio:[legacy,photo,event])]
    XCTAssertEqual(captroProfessionalMoments([legacy,photo,event],user:user).map(\.id),["photo"])
    XCTAssertEqual(captroProfessionalMoments([legacy,photo,event],user:nil).map(\.id),["photo"])
  }
}
