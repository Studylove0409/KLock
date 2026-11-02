import Foundation

/// 一次计时结束的记录。
struct TimerRecord: Codable, Identifiable, Equatable {
  let id: UUID
  let name: String
  let duration: TimeInterval
  let finishedAt: Date
}

/// 计时历史，最多保留 200 条，存在 UserDefaults 里。
final class HistoryStore {
  static let shared = HistoryStore()

  private let storageKey = "TimerHistory"
  private let limit = 200
  private(set) var records: [TimerRecord] = []

  private init() {
    records = HistoryStore.decode(
      UserDefaults.standard.data(forKey: storageKey) ?? Data()) ?? []
  }

  func add(name: String, duration: TimeInterval, finishedAt: Date = Date()) {
    records.insert(
      TimerRecord(
        id: UUID(), name: name, duration: duration, finishedAt: finishedAt),
      at: 0)
    if records.count > limit {
      records = Array(records.prefix(limit))
    }
    persist()
  }

  func clear() {
    records = []
    persist()
  }

  private func persist() {
    UserDefaults.standard.set(
      HistoryStore.encode(records), forKey: storageKey)
  }

  // MARK: - 纯编解码，方便脱离 App 测试

  static func encode(_ records: [TimerRecord]) -> Data? {
    try? JSONEncoder().encode(records)
  }

  static func decode(_ data: Data) -> [TimerRecord]? {
    try? JSONDecoder().decode([TimerRecord].self, from: data)
  }
}
