import AppKit

protocol AlarmSoundPlaying: AnyObject {
  var loops: Bool { get set }
  var volume: Float { get set }
  @discardableResult func play() -> Bool
  @discardableResult func stop() -> Bool
}

extension NSSound: AlarmSoundPlaying {}

class SoundManager: NSObject, NSSoundDelegate {
  static let shared = SoundManager()

  let allowedExtensions = ["mp3", "wav", "aiff", "caf", "m4a"]
  private let soundFactory: (URL, Bool) -> AlarmSoundPlaying?
  private struct Playback {
    let sound: AlarmSoundPlaying
    let scopedURL: URL?
  }
  private var activeSounds: [UUID: Playback] = [:]

  init(soundFactory: @escaping (URL, Bool) -> AlarmSoundPlaying? = {
    NSSound(contentsOf: $0, byReference: $1)
  }) {
    self.soundFactory = soundFactory
    super.init()
  }

  deinit {
    stopAllSounds()
  }

  func availableAlarmSounds() -> [String] {
    var names: [String] = []
    for ext in allowedExtensions {
      if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
        names.append(contentsOf: urls.map { $0.lastPathComponent })
      }
    }
    return Array(Set(names)).sorted()
  }

  func playSelectedAlarmIfEnabled(for timerId: UUID, loop: Bool = false) {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: "playAlarmSound") else { return }

    stopSound(for: timerId)

    if defaults.bool(forKey: "useCustomAlarmSound"),
      playCustomSoundIfAvailable(for: timerId, loop: loop)
    {
      return
    }

    playPredefinedSoundFallback(for: timerId, loop: loop)
  }

  private func playPredefinedSoundFallback(for timerId: UUID, loop: Bool) {
    let preferredSound = UserDefaults.standard.string(forKey: "selectedAlarmSound")
    if let preferredSound = preferredSound,
      play(soundNamed: preferredSound, for: timerId, loop: loop)
    {
      return
    }

    if let fallback = availableAlarmSounds().first {
      _ = play(soundNamed: fallback, for: timerId, loop: loop)
    }
  }

  @discardableResult
  func play(soundNamed name: String, for timerId: UUID, loop: Bool = false) -> Bool {
    guard let url = soundURL(for: name) else {
      print("SoundManager: could not find sound named \(name)")
      return false
    }

    return playSound(at: url, for: timerId, loop: loop)
  }

  @discardableResult
  func playSound(
    at url: URL, for timerId: UUID, loop: Bool = false,
    byReference: Bool = false, scopedURL: URL? = nil
  ) -> Bool {
    stopSound(for: timerId)
    guard let sound = soundFactory(url, byReference) else {
      scopedURL?.stopAccessingSecurityScopedResource()
      return false
    }
    sound.loops = loop
    sound.volume = 1.0
    (sound as? NSSound)?.delegate = self
    guard sound.play() else {
      scopedURL?.stopAccessingSecurityScopedResource()
      return false
    }
    activeSounds[timerId] = Playback(sound: sound, scopedURL: scopedURL)
    return true
  }

  func stopSound(for timerId: UUID) {
    guard let playback = activeSounds.removeValue(forKey: timerId) else { return }
    playback.sound.stop()
    playback.scopedURL?.stopAccessingSecurityScopedResource()
  }

  func stopAllSounds() {
    let playbacks = Array(activeSounds.values)
    activeSounds.removeAll()
    for playback in playbacks {
      playback.sound.stop()
      playback.scopedURL?.stopAccessingSecurityScopedResource()
    }
  }

  func sound(_ sound: NSSound, didFinishPlaying successfully: Bool) {
    DispatchQueue.main.async { [weak self, weak sound] in
      guard let self = self, let sound = sound,
        let timerId = self.activeSounds.first(where: { $0.value.sound === sound })?.key,
        let playback = self.activeSounds.removeValue(forKey: timerId)
      else { return }
      playback.scopedURL?.stopAccessingSecurityScopedResource()
    }
  }

  private func playCustomSoundIfAvailable(for timerId: UUID, loop: Bool) -> Bool {
    guard
      let bookmark = UserDefaults.standard.data(
        forKey: "customAlarmSoundBookmark")
    else { return false }

    do {
      var stale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &stale)

      if stale {
        let refreshed = try url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil)
        UserDefaults.standard.set(
          refreshed, forKey: "customAlarmSoundBookmark")
      }

      guard url.startAccessingSecurityScopedResource() else { return false }
      return playSound(
        at: url, for: timerId, loop: loop, byReference: true, scopedURL: url)
    } catch {
      print("SoundManager: failed to load custom sound - \(error)")
    }
    // 失败时返回 false，由调用方统一回退到内置音效，避免重复播放。
    return false
  }

  private func soundURL(for name: String) -> URL? {
    if let range = name.range(of: ".", options: .backwards) {
      let base = String(name[..<range.lowerBound])
      let ext = String(name[range.upperBound...])
      if let url = Bundle.main.url(forResource: base, withExtension: ext) {
        return url
      }
    }

    for ext in allowedExtensions {
      if let url = Bundle.main.url(forResource: name, withExtension: ext) {
        return url
      }
    }
    return nil
  }
}
