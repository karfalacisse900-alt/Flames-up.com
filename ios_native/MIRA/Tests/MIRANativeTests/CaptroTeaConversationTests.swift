import XCTest
@testable import MIRANative

final class CaptroTeaConversationTests: XCTestCase {
  func testDomainsUseExactBoundariesAndPreserveDestinations() {
    XCTAssertEqual(CaptroTeaLink("https://www.youtube.com/watch?v=a&signature=keep")?.hostname,"youtube.com")
    XCTAssertEqual(CaptroTeaLink("https://www.youtube.com/watch?v=a&signature=keep")?.url.query,"v=a&signature=keep")
    XCTAssertEqual(CaptroTeaLink("https://youtu.be/a")?.platform,"YouTube")
    XCTAssertEqual(CaptroTeaLink("https://m.tiktok.com/a")?.platform,"TikTok")
    for host in ["youtube.com.evil.example","notyoutube.com","tiktok.com.evil.example","example.com"] {
      XCTAssertNil(CaptroTeaLink("https://"+host)?.platform)
    }
    for value in ["http://youtube.com","https://user:secret@youtube.com","javascript:alert(1)","https://localhost","https://127.0.0.1","https://example.com\n"] {
      XCTAssertNil(CaptroTeaLink(value))
    }
  }
  func testOnlySupportedCaptroPathsRouteToProfile() {
    XCTAssertEqual(CaptroTeaLink("https://captro-site.pages.dev/profile/user_123")?.profile?.id,"user_123")
    XCTAssertNil(CaptroTeaLink("https://captro-site.pages.dev.evil.example/profile/user_123")?.profile)
    XCTAssertNil(CaptroTeaLink("https://captro-site.pages.dev/unknown/user_123")?.profile)
    XCTAssertNil(CaptroTeaLink("https://captro-site.pages.dev/profile/user_123?redirect=other")?.profile)
  }
  func testConversationDecodingOmitsUnrecognizedStoredAuthorUpdateData() throws {
    let data = Data(#"{"id":"test","title":"A title","body":"Text","links":[],"author":{"id":"a","name":"Artist","username":"artist"},"createdAt":"2026-11-13T12:00:00Z","version":1,"isAuthor":false,"following":false,"author_update":{"body":"Old stored value"}}"#.utf8)
    let value=try JSONDecoder().decode(CaptroTeaConversation.self,from:data)
    XCTAssertTrue(value.links.isEmpty);XCTAssertEqual(value.body,"Text")
    XCTAssertNotNil(captroTeaDate(value.createdAt))
  }
}
