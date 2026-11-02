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
}
