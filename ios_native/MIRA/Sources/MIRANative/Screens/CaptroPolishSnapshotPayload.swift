#if DEBUG
import Foundation
// The no-deployment review workflow generates this payload on its isolated runner.
// Real Notes and photo bytes are never checked in or bundled in Release builds.
enum CaptroPolishSnapshotPayload { static let data = Data("{}".utf8) }
#endif
