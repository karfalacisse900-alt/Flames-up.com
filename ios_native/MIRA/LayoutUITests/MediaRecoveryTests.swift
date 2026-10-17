import XCTest
import UIKit

final class MediaRecoveryTests: XCTestCase {
  func testHomeRetryDisplaysCorrectPixelsWithoutOpeningDetailsOrMovingMedia() {
    let app=XCUIApplication()
    app.launchArguments=["--captro-design-quality-test","--captro-favorites-review","--review-empty","--captro-image-recovery-review"]
    app.launch()
    let retry=app.buttons["media.image.retry"]
    XCTAssertTrue(retry.waitForExistence(timeout:20));XCTAssertTrue(retry.isHittable)
    let media=app.descendants(matching:.any)["home.post.media"].firstMatch
    let before=media.frame
    capture(app,"home-image-corrupt-recoverable")
    retry.tap()
    XCTAssertTrue(retry.waitForNonExistence(timeout:8))
    XCTAssertFalse(app.buttons["post.detail.options"].exists,"Retry must not bubble into the post-open gesture")
    XCTAssertEqual(media.frame.minY,before.minY,accuracy:1);XCTAssertEqual(media.frame.height,before.height,accuracy:1)
    assertRed(app,in:media.frame);capture(app,"home-image-retry-loaded")
    media.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.25)).tap()
    XCTAssertTrue(app.buttons["post.detail.options"].waitForExistence(timeout:8))
    let detail=app.descendants(matching:.any)["post.detail.media"].firstMatch
    XCTAssertTrue(detail.waitForExistence(timeout:8));assertRed(app,in:detail.frame)
    capture(app,"details-same-cached-image")
  }
  private func assertRed(_ app:XCUIApplication,in frame:CGRect) {
    let screenshot=app.screenshot().image
    guard let cg=screenshot.cgImage else {return XCTFail("No screenshot")}
    let scale=CGFloat(cg.width)/app.frame.width
    let point=CGPoint(x:frame.midX*scale,y:(frame.minY+frame.height*0.25)*scale)
    guard let sample=cg.cropping(to:CGRect(x:point.x,y:point.y,width:2,height:2)) else {return XCTFail("Image sample outside screen")}
    var pixel=[UInt8](repeating:0,count:4)
    let context=CGContext(data:&pixel,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,
      space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(sample,in:CGRect(x:0,y:0,width:1,height:1))
    XCTAssertGreaterThan(pixel[0],220);XCTAssertLessThan(pixel[1],30);XCTAssertLessThan(pixel[2],30)
  }
  private func capture(_ app:XCUIApplication,_ name:String) {
    let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
  }
}
