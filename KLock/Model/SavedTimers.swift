import AppKit

struct SavedTimer: Codable {
  let id: String
  let name: String?
  let startTime: Date
  let duration: TimeInterval
  let reminderId: String?
  /// 循环闹铃时，已结束但还没被用户删掉的计时器需要记住这个状态，
  /// 否则重启后会被当成「刚刚结束」再次提醒。旧数据没有这个字段。
  var isFinished: Bool?
  /// 暂停时冻结的剩余秒数；nil 表示正在计时。
  var pausedRemaining: TimeInterval?
  /// 对应历史记录的 id，用于把「进行中」改写为「已完成」或「已取消」。
  var recordId: String?
}
