#if DEBUG
import Foundation
import UIKit

/// Only the explicit offline UI-review launch installs this on the shared loader.
/// Exercise real HTTP/decode/cache/view transitions; no production URL is used.
final class CaptroImageRecoveryFixtureProtocol: URLProtocol {
  static let mediaURL = "https://image-fixture.invalid/\(UUID().uuidString)/photo.png"
  private static let lock = NSLock()
  private static var attempts: [String:Int] = [:]
  private var stopped = false
  private let lock = NSLock()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let key=request.url!.absoluteString
    let attempt=Self.lock.withLock { Self.attempts[key,default:0] += 1;return Self.attempts[key]! }
    DispatchQueue.global().asyncAfter(deadline:.now()+0.15) { [self] in
      guard !lock.withLock({stopped}) else { return }
      let data:Data
      if attempt==1 { data=Data("corrupt fixture".utf8) }
      else {
        let context=CGContext(data:nil,width:16,height:20,bitsPerComponent:8,bytesPerRow:64,
          space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(UIColor.red.cgColor);context.fill(CGRect(x:0,y:0,width:16,height:20))
        data=UIImage(cgImage:context.makeImage()!).pngData()!
      }
      client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"image/png"])!,cacheStoragePolicy:.notAllowed)
      client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() { lock.withLock { stopped=true } }
}
#endif
