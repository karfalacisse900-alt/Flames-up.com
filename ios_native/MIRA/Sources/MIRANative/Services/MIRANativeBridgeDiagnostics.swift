import Foundation
import MIRACoreCpp

public enum MIRANativeBridgeDiagnostics {
  /// Calls a non-secret, deterministic Rust function so startup diagnostics prove the native
  /// bridge is present and executable. No wallet, token, receipt, or user data crosses this probe.
  @discardableResult
  public static func verifyStartupLinkage() -> Bool {
    let probe = Array("aura-ios-static-link-probe".utf8)
    let result = probe.withUnsafeBytes { buffer in
      mira_rust_hash_bytes(
        buffer.bindMemory(to: UInt8.self).baseAddress,
        buffer.count
      )
    }
    let available = result != 0
    MIRAApplePerformanceLogger.event(
      available ? "native_rust_bridge_ready" : "native_rust_bridge_probe_failed"
    )
    return available
  }
}
