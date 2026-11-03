import Foundation

enum TimerRecordStatus: String, Codable {
  case active      // 正在计时或暂停中
  case finished    // 正常结束
  case cancelled   // 被手动删除

  var label: String {
    switch self {
    case .active: return "进行中"
    case .finished: return "已完成"
    case .cancelled: return "已取消"
    }
  }
}

/// 一次计时的记录：创建时就落档，结束时改写状态。
struct TimerRecord: Codable, Identifiable, Equatable {
  let id: UUID
  var name: String
  var duration: TimeInterval
  var createdAt: Date
  var finishedAt: Date?
  var status: TimerRecordStatus

  init(
    id: UUID = UUID(),
    name: String,
    duration: TimeInterval,
    createdAt: Date,
    finishedAt: Date? = nil,
    status: TimerRecordStatus
  ) {
    self.id = id
    self.name = name
    self.duration = duration
    self.createdAt = createdAt
    self.finishedAt = finishedAt
    self.status = status
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, duration, createdAt, finishedAt, status
  }

  /// 兼容早期只记录「已完成」的存档：缺 createdAt / status 时补默认值。
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    duration = try container.decode(TimeInterval.self, forKey: .duration)
    let finished = try container.decodeIfPresent(
      Date.self, forKey: .finishedAt)
    finishedAt = finished
    createdAt =
      try container.decodeIfPresent(Date.self, forKey: .createdAt)
      ?? finished ?? Date()
    status =
      try container.decodeIfPresent(TimerRecordStatus.self, forKey: .status)
      ?? .finished
  }
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

  /// 创建计时器时调用，返回记录 id，后续用来改写状态。
  func recordCreated(
    name: String, duration: TimeInterval, at date: Date = Date()
  ) -> UUID {
    let record = TimerRecord(
      name: name, duration: duration, createdAt: date, status: .active)
    records.insert(record, at: 0)
    trim()
    persist()
    return record.id
  }

  func markFinished(recordId: UUID, at date: Date = Date()) {
    update(recordId) { record in
      record.status = .finished
      record.finishedAt = date
    }
  }

  func markCancelled(recordId: UUID) {
    update(recordId) { record in
      guard record.status == .active else { return }
      record.status = .cancelled
    }
  }

  func clear() {
    records = []
    persist()
  }

  private func update(_ recordId: UUID, change: (inout TimerRecord) -> Void) {
    guard let index = records.firstIndex(where: { $0.id == recordId })
    else { return }
    change(&records[index])
    persist()
  }

  private func trim() {
    if records.count > limit {
      records = Array(records.prefix(limit))
    }
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
