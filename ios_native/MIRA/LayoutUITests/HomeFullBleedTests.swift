import XCTest

final class HomeFullBleedTests: XCTestCase {
  func testHomePagerRepeatedSwipesReversalAndPostOpening() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-home-feed-visual-test", "--captro-visual-pager", "--captro-visual-size=portrait"]
    app.launch()

    let pager = app.scrollViews["home.post.pager"]
    XCTAssertTrue(pager.waitForExistence(timeout: 15))
    let fixedControls = app.otherElements["home.fixed.controls"]
    let storyRail = app.scrollViews["home.story.rail"]
    XCTAssertTrue(fixedControls.waitForExistence(timeout: 5))
    XCTAssertTrue(storyRail.waitForExistence(timeout: 5))
    XCTAssertGreaterThanOrEqual(storyRail.frame.minX, fixedControls.frame.maxX - 1,
                                "Stories must be clipped before they reach NYC and Post")
    func assertVisiblePost(_ index: Int) {
      let page = app.otherElements["home.post.page.full-bleed-portrait-\(index)"]
      XCTAssertTrue(page.waitForExistence(timeout: 5), "Expected post \(index + 1) to be current")
      XCTAssertTrue(page.isHittable)
    }

    assertVisiblePost(0)
    pager.swipeLeft()
    assertVisiblePost(1)
    pager.swipeLeft()
    assertVisiblePost(2)
    pager.swipeLeft() // The last post must not skip or wrap.
    assertVisiblePost(2)
    pager.swipeRight()
    assertVisiblePost(1)
    pager.swipeRight()
    assertVisiblePost(0)

    XCTAssertFalse(app.buttons["Back"].exists, "A swipe must not open the post")
    let media = app.otherElements["home.post.media"].firstMatch
    XCTAssertTrue(media.waitForExistence(timeout: 5))
    media.tap()
    XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5))
    app.buttons["Back"].tap()
    assertVisiblePost(0)
  }

  func testVideoFillsScreenWidth() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--captro-home-feed-visual-test", "--captro-visual-size=threefour", "--captro-visual-video"]
    app.launch()
    let media = app.otherElements["home.post.media"].firstMatch
    XCTAssertTrue(media.waitForExistence(timeout: 15))
    XCTAssertEqual(media.frame.minX, 0, accuracy: 0.5)
    XCTAssertEqual(media.frame.maxX, app.frame.width, accuracy: 0.5)
    XCTAssertTrue(app.buttons["Pause video"].firstMatch.waitForExistence(timeout: 10))
    app.buttons["Pause video"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Play video"].firstMatch.waitForExistence(timeout: 3))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "full-bleed-video"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.terminate()
  }

  func testEveryPhotoRatioFillsScreenWidth() throws {
    for ratio in ["landscape", "portrait", "fourfive", "threefour", "square"] {
      let app = XCUIApplication()
      app.launchArguments = ["--captro-home-feed-visual-test", "--captro-visual-size=\(ratio)"]
      app.launch()
      let media = app.otherElements["home.post.media"].firstMatch
      XCTAssertTrue(media.waitForExistence(timeout: 15), "Missing media for \(ratio)")
      XCTAssertEqual(media.frame.minX, 0, accuracy: 0.5, "Left gutter for \(ratio)")
      XCTAssertEqual(media.frame.maxX, app.frame.width, accuracy: 0.5, "Right gutter for \(ratio)")
      XCTAssertGreaterThan(media.frame.height, 100)
      XCTAssertLessThanOrEqual(media.frame.maxY, app.frame.maxY)
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "full-bleed-\(ratio)"
      attachment.lifetime = .keepAlways
      add(attachment)
      app.terminate()
    }
  }
}
