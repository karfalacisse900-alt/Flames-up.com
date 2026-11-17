import XCTest
import Foundation
@testable import MIRANative

final class CaptroTeaNoteTests: XCTestCase {
  func testOldNoteDecodesAndOptionalFieldsClearExplicitly() throws {
    let note = try JSONDecoder().decode(CaptroTeaConversation.self, from: NoteProtocol.noteData)
    XCTAssertNil(note.borough); XCTAssertNil(note.primaryAction)
    let payload = CaptroTeaNotePayload(title: note.title, body: note.body, links: [], requestID: nil, version: 1, borough: nil, primaryAction: nil)
    let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(payload)) as? [String:Any])
    XCTAssertTrue(json["borough"] is NSNull); XCTAssertTrue(json["primary_action"] is NSNull)
    XCTAssertNil(json["request_id"])
  }
  func testActionEncodingNeverSendsServerStateOrRecipient() throws {
    let action = CaptroTeaNoteAction(kind: "listing", label: "View deal", listingId: UUID().uuidString, state: "active")
    let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
    let payload = CaptroTeaNotePayload(title: "Opening", body: "A neighborhood offer", links: [], requestID: UUID().uuidString, version: nil, borough: "Queens", primaryAction: action)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(payload)) as? [String:Any])
    let input = try XCTUnwrap(json["primary_action"] as? [String:Any])
    XCTAssertEqual(Set(input.keys), ["kind","label","listing_id"])
    XCTAssertEqual(json["borough"] as? String, "Queens")
    for url in ["http://example.com","javascript:alert(1)","https://user:password@example.com","https://127.0.0.1","https://app.local"] {
      XCTAssertFalse(CaptroTeaNoteAction(kind: "external", label: "Apply", url: url).valid)
    }
    XCTAssertTrue(CaptroTeaNoteAction(kind: "external", label: "Join the test", url: "https://example.com/signup").valid)
  }
  @MainActor func testApplicationRetryIsStableDraftSurvivesAndLogoutErasesPrivateData() async throws {
    NoteProtocol.reset()
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [NoteProtocol.self]
    let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
    let api = MIRAAPIClient(session: session)
    var note = try JSONDecoder().decode(CaptroTeaConversation.self, from: NoteProtocol.noteData)
    note.primaryAction = CaptroTeaNoteAction(kind: "application", label: "Apply", heightRequested: false, accepting: true, state: "active")
    let model = api.teaConversations.application(for: note)
    model.fullName = "Test Applicant"; model.availability = "Weekends"
    await model.submit()
    XCTAssertFalse(model.confirmed); XCTAssertNotNil(model.pending); XCTAssertNotNil(model.error)
    XCTAssertTrue(api.teaConversations.application(for: note) === model)
    XCTAssertEqual(model.availability,"Weekends")
    model.availability = "Changed after uncertain response"
    async let first: Void = model.submit(); async let second: Void = model.submit(); _ = await (first,second)
    XCTAssertTrue(model.confirmed)
    let bodies = NoteProtocol.payloads()
    XCTAssertEqual(bodies.count,2)
    XCTAssertEqual(bodies[0]["request_id"] as? String,bodies[1]["request_id"] as? String)
    XCTAssertEqual(bodies[1]["availability"] as? String,"Weekends")
    XCTAssertEqual(model.fullName, "")
    model.fullName = "Private draft"; api.teaConversations.invalidate()
    XCTAssertFalse(model.validScope); XCTAssertEqual(model.fullName, ""); XCTAssertNil(model.pending)
  }
}

private final class NoteProtocol: URLProtocol, @unchecked Sendable {
  static let noteData = Data(#"{"id":"00000000-0000-4000-8000-000000000101","title":"Casting","body":"Join our shoot","links":[],"author":{"id":"agency","name":"Agency","username":"agency"},"createdAt":"2026-11-17T10:00:00Z","version":1,"isAuthor":false,"following":false}"#.utf8)
  private static let lock = NSLock()
  private static var bodies: [[String:Any]] = []
  static func reset() { lock.withLock { bodies = [] } }
  static func payloads() -> [[String:Any]] { lock.withLock { bodies } }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var bytes = [UInt8](repeating:0,count:1024)
      while stream.hasBytesAvailable { let count = stream.read(&bytes,maxLength:bytes.count); if count <= 0 { break }; data.append(contentsOf:bytes.prefix(count)) }
    }
    let payload = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
    let count = Self.lock.withLock { Self.bodies.append(payload); return Self.bodies.count }
    let status = count == 1 ? 503 : 200
    let response = status == 503 ? #"{"detail":"Offline"}"# : #"{"id":"receipt","confirmed":true,"submittedAt":"2026-11-17T10:01:00Z"}"#
    client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
    client?.urlProtocol(self,didLoad:Data(response.utf8)); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
