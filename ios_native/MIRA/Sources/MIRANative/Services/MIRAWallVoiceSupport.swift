import AVFoundation
import Foundation
import SwiftUI
import UIKit

@MainActor
final class MIRAWallVoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
  enum State: Equatable {
    case idle
    case recording
    case paused
    case ready
    case denied
    case failed(String)
  }

  static let maximumDuration: TimeInterval = 60

  @Published private(set) var state: State = .idle
  @Published private(set) var duration: TimeInterval = 0
  @Published private(set) var waveform: [Double] = []

  private var recorder: AVAudioRecorder?
  private var meterTimer: Timer?
  private var recordingURL: URL?
  private var observers: [NSObjectProtocol] = []

  override init() {
    super.init()
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.pauseForInterruption() }
    })
    observers.append(center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.pauseForInterruption() }
    })
  }

  deinit {
    meterTimer?.invalidate()
    observers.forEach(NotificationCenter.default.removeObserver)
  }

  func start() async {
    guard state != .recording else { return }
    guard await microphonePermission() else {
      state = .denied
      return
    }

    do {
      cancel(removeFile: true)
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.record, mode: .spokenAudio, options: [.allowBluetooth])
      try session.setActive(true, options: .notifyOthersOnDeactivation)

      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("captro-wall-voice-\(UUID().uuidString).m4a")
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 128_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder.delegate = self
      recorder.isMeteringEnabled = true
      guard recorder.prepareToRecord(), recorder.record(forDuration: Self.maximumDuration) else {
        throw MIRAWallVoiceError.recordingUnavailable
      }
      self.recorder = recorder
      recordingURL = url
      duration = 0
      waveform = []
      state = .recording
      startMetering()
    } catch {
      state = .failed(error.localizedDescription)
      stopMetering()
    }
  }

  func pause() {
    guard state == .recording else { return }
    recorder?.pause()
    duration = recorder?.currentTime ?? duration
    state = .paused
    stopMetering()
  }

  func resume() {
    guard state == .paused, let recorder else { return }
    guard recorder.record(forDuration: max(0.25, Self.maximumDuration - recorder.currentTime)) else {
      state = .failed(MIRAWallVoiceError.recordingUnavailable.localizedDescription)
      return
    }
    state = .recording
    startMetering()
  }

  func finish() {
    guard state == .recording || state == .paused else { return }
    recorder?.stop()
    duration = recorder?.currentTime ?? duration
    stopMetering()
    state = duration >= 0.25 ? .ready : .failed("Record at least a quarter second.")
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func cancel(removeFile: Bool = true) {
    recorder?.stop()
    recorder = nil
    stopMetering()
    if removeFile, let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
    recordingURL = nil
    duration = 0
    waveform = []
    state = .idle
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func recordedData() throws -> Data {
    guard state == .ready, let recordingURL else { throw MIRAWallVoiceError.missingRecording }
    return try Data(contentsOf: recordingURL, options: .mappedIfSafe)
  }

  func previewURL() -> URL? { state == .ready ? recordingURL : nil }

  func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
    duration = recorder.currentTime
    stopMetering()
    state = flag && duration >= 0.25 ? .ready : .failed("The recording could not be completed.")
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func pauseForInterruption() {
    if state == .recording { pause() }
  }

  private func microphonePermission() async -> Bool {
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted:
      return true
    case .denied:
      return false
    case .undetermined:
      return await withCheckedContinuation { continuation in
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      }
    @unknown default:
      return false
    }
  }

  private func startMetering() {
    stopMetering()
    meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.sampleMeter() }
    }
  }

  private func stopMetering() {
    meterTimer?.invalidate()
    meterTimer = nil
  }

  private func sampleMeter() {
    guard let recorder, state == .recording else { return }
    recorder.updateMeters()
    duration = min(Self.maximumDuration, recorder.currentTime)
    let decibels = recorder.averagePower(forChannel: 0)
    let normalized = max(0.04, min(1, pow(10, Double(decibels) / 34)))
    waveform.append(normalized)
    if waveform.count > 48 {
      let pairs = stride(from: 0, to: waveform.count, by: 2).map { index -> Double in
        let next = min(index + 1, waveform.count - 1)
        return max(waveform[index], waveform[next])
      }
      waveform = Array(pairs.suffix(48))
    }
    if duration >= Self.maximumDuration { finish() }
  }
}

@MainActor
final class MIRAWallVoicePlaybackController: ObservableObject {
  static let shared = MIRAWallVoicePlaybackController()

  @Published private(set) var activeID: String?
  @Published private(set) var isPlaying = false
  @Published private(set) var progress: Double = 0
  @Published private(set) var elapsed: TimeInterval = 0
  @Published private(set) var errorMessage: String?

  private var player: AVPlayer?
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var failedObserver: NSObjectProtocol?
  private var stalledObserver: NSObjectProtocol?
  private var itemStatusObservation: NSKeyValueObservation?
  private var playbackStatusObservation: NSKeyValueObservation?
  private var lifecycleObservers: [NSObjectProtocol] = []
  private var shouldResumeAfterForeground = false
  private var shouldResumeAfterInterruption = false

  private init() {
    let center = NotificationCenter.default
    lifecycleObservers.append(center.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor [weak self] in self?.handleInterruption(notification) }
    })
    lifecycleObservers.append(center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.pauseForBackground() }
    })
    lifecycleObservers.append(center.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.resumeAfterForegroundIfNeeded() }
    })
  }

  deinit {
    for observer in lifecycleObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func toggle(id: String, url: URL) {
    if activeID == id, let player {
      if isPlaying {
        player.pause()
        isPlaying = false
        shouldResumeAfterForeground = false
        shouldResumeAfterInterruption = false
      } else {
        guard activatePlaybackSession() else { return }
        errorMessage = nil
        player.play()
        isPlaying = true
      }
      return
    }
    play(id: id, url: url)
  }

  func play(id: String, url: URL) {
    stop()
    activeID = id
    guard activatePlaybackSession() else { return }
    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    self.player = player
    errorMessage = nil
    observe(player: player, item: item)
    player.play()
    isPlaying = true
  }

  func stop() {
    player?.pause()
    removeObservers()
    player = nil
    activeID = nil
    isPlaying = false
    progress = 0
    elapsed = 0
    errorMessage = nil
    shouldResumeAfterForeground = false
    shouldResumeAfterInterruption = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func handleInterruption(_ notification: Notification) {
    let value = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
    guard let value, let type = AVAudioSession.InterruptionType(rawValue: value) else {
      shouldResumeAfterInterruption = isPlaying
      pausePreservingPlayback()
      return
    }

    switch type {
    case .began:
      shouldResumeAfterInterruption = isPlaying
      pausePreservingPlayback()
    case .ended:
      let rawOptions = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
      let mayResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
      let requestedResume = shouldResumeAfterInterruption && mayResume
      shouldResumeAfterInterruption = false
      if requestedResume, UIApplication.shared.applicationState == .active {
        resumePreservingPlayback()
      } else if requestedResume {
        shouldResumeAfterForeground = true
      }
    @unknown default:
      shouldResumeAfterInterruption = false
    }
  }

  private func pauseForBackground() {
    guard player != nil else { return }
    shouldResumeAfterForeground = isPlaying || shouldResumeAfterInterruption
    pausePreservingPlayback()
  }

  private func resumeAfterForegroundIfNeeded() {
    guard shouldResumeAfterForeground else { return }
    shouldResumeAfterForeground = false
    resumePreservingPlayback()
  }

  private func pausePreservingPlayback() {
    player?.pause()
    isPlaying = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func resumePreservingPlayback() {
    guard let player else { return }
    guard activatePlaybackSession() else { return }
    errorMessage = nil
    player.play()
    isPlaying = true
  }

  private func observe(player: AVPlayer, item: AVPlayerItem) {
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
      queue: .main
    ) { [weak self, weak item] time in
      Task { @MainActor [weak self, weak item] in
        guard let self else { return }
        elapsed = max(0, time.seconds.isFinite ? time.seconds : 0)
        let duration = item?.duration.seconds ?? 0
        progress = duration.isFinite && duration > 0 ? min(1, elapsed / duration) : 0
      }
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in self?.stop() }
    }
    failedObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemFailedToPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.finishWithPlaybackError("This voice note could not be played. Try again.")
      }
    }
    stalledObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemPlaybackStalled,
      object: item,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.isPlaying = false
        self?.errorMessage = "Voice note is buffering. Tap play to retry."
      }
    }
    itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
      Task { @MainActor [weak self, weak item] in
        guard let self, let item else { return }
        if item.status == .failed {
          finishWithPlaybackError("This voice note could not be played. Try again.")
        }
      }
    }
    playbackStatusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self, weak player] _, _ in
      Task { @MainActor [weak self, weak player] in
        guard let self, let player else { return }
        switch player.timeControlStatus {
        case .playing:
          isPlaying = true
          errorMessage = nil
        case .paused:
          isPlaying = false
        case .waitingToPlayAtSpecifiedRate:
          isPlaying = false
        @unknown default:
          isPlaying = false
        }
      }
    }
  }

  private func removeObservers() {
    if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
    timeObserver = nil
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    endObserver = nil
    if let failedObserver { NotificationCenter.default.removeObserver(failedObserver) }
    failedObserver = nil
    if let stalledObserver { NotificationCenter.default.removeObserver(stalledObserver) }
    stalledObserver = nil
    itemStatusObservation?.invalidate()
    itemStatusObservation = nil
    playbackStatusObservation?.invalidate()
    playbackStatusObservation = nil
  }

  private func finishWithPlaybackError(_ message: String) {
    player?.pause()
    removeObservers()
    player = nil
    isPlaying = false
    progress = 0
    elapsed = 0
    errorMessage = message
    shouldResumeAfterForeground = false
    shouldResumeAfterInterruption = false
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func activatePlaybackSession() -> Bool {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio, options: [])
      try session.setActive(true)
      return true
    } catch {
      errorMessage = "Audio is unavailable right now."
      isPlaying = false
      return false
    }
  }
}

struct MIRAWallWaveformView: View {
  let samples: [Double]
  var progress: Double = 0
  var tint: Color = .black

  var body: some View {
    GeometryReader { proxy in
      let values = samples.isEmpty ? Array(repeating: 0.24, count: 24) : samples
      let spacing: CGFloat = 2
      let width = max(1.5, (proxy.size.width - spacing * CGFloat(values.count - 1)) / CGFloat(values.count))
      HStack(alignment: .center, spacing: spacing) {
        ForEach(Array(values.enumerated()), id: \.offset) { index, value in
          Capsule()
            .fill(tint.opacity(Double(index) / Double(max(1, values.count - 1)) <= progress ? 0.92 : 0.32))
            .frame(width: width, height: max(3, proxy.size.height * CGFloat(max(0.08, min(1, value)))))
        }
      }
      .frame(maxHeight: .infinity)
    }
    .accessibilityHidden(true)
  }
}

private enum MIRAWallVoiceError: LocalizedError {
  case recordingUnavailable
  case missingRecording

  var errorDescription: String? {
    switch self {
    case .recordingUnavailable: "Voice recording is unavailable right now."
    case .missingRecording: "The voice recording is missing. Please record it again."
    }
  }
}
