import EventKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

fileprivate extension View {
  @ViewBuilder
  func onChangeCompat<Value: Equatable>(_ value: Value, publisher: Published<Value>.Publisher, perform: @escaping (Value) -> Void) -> some View {
    if #available(macOS 14, *) {
      self.onChange(of: value) { newValue in
        perform(newValue)
      }
    } else {
      self.onReceive(publisher.dropFirst()) { newValue in
        perform(newValue)
      }
    }
  }

  @ViewBuilder
  func onChangeCompat<Value>(_ publisher: Published<Value>.Publisher, perform: @escaping (Value) -> Void) -> some View {
    self.onReceive(publisher.dropFirst(), perform: perform)
  }
}

enum PreferenceTab {
  case general
  case reminders
  case timers
}

struct PreferencesView: View {
  @StateObject private var viewModel = PreferencesViewModel()
  @State private var selectedTab: PreferenceTab = .general
  @State private var isShowingSoundImporter: Bool = false

  private var notificationStatusText: String {
    switch viewModel.notificationsAuthorized {
    case .none: return "检测中…"
    case .some(true): return "已允许"
    case .some(false): return "未允许"
    }
  }

  private static let tabs: [(
    tab: PreferenceTab, icon: String, label: String, subtitle: String
  )] = [
    (.general, "gearshape", "通用", "启动、菜单栏显示与外观"),
    (.reminders, "bell.badge", "提醒事项", "与系统「提醒事项」联动"),
    (.timers, "timer", "计时器", "命名、闹铃与拖拽步进"),
  ]

  private var currentTab: (
    tab: PreferenceTab, icon: String, label: String, subtitle: String
  ) {
    Self.tabs.first { $0.tab == selectedTab } ?? Self.tabs[0]
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebar

      // 1pt 分隔线，跟随明暗模式
      Rectangle()
        .fill(Color.primary.opacity(0.07))
        .frame(width: 1)

      contentPane
    }
    .frame(minWidth: 700, minHeight: 500)
    .background(GlassBackground(material: .sidebar).ignoresSafeArea())
    .onAppear {
      viewModel.loadPreferences()
      viewModel.refreshPermissionStatus()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      viewModel.refreshPermissionStatus()
    }
    .fileImporter(
      isPresented: $isShowingSoundImporter,
      allowedContentTypes: SoundManager.shared.allowedExtensions.compactMap {
        UTType(filenameExtension: $0)
      }
    ) { result in
      switch result {
      case .success(let url):
        viewModel.storeCustomAlarmSound(url: url)
      case .failure(let error):
        print("File import failed: \(error)")
      }
    }
  }

  // MARK: - 侧栏

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 7) {
        Image(systemName: "timer")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
        Text("KLock")
          .font(.system(size: 13, weight: .semibold))
      }
      .padding(.horizontal, 9)
      .padding(.top, 38)
      .padding(.bottom, 14)

      ForEach(Self.tabs, id: \.tab) { item in
        SettingsTabButton(
          icon: item.icon,
          label: item.label,
          isSelected: selectedTab == item.tab
        ) {
          selectedTab = item.tab
        }
      }

      Spacer(minLength: 0)

      Text("1.9")
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
    }
    .padding(.horizontal, 10)
    .frame(width: 196)
  }

  // MARK: - 内容区

  private var contentPane: some View {
    GeometryReader { geometry in
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            // 锚点放在内容边距之外，短页和可滚动页回到同一顶部位置。
            Color.clear.frame(height: 0).id("contentTop")

            VStack(alignment: .leading, spacing: 20) {
              VStack(alignment: .leading, spacing: 3) {
                Text(currentTab.label)
                  .font(.system(size: 17, weight: .semibold))
                Text(currentTab.subtitle)
                  .font(.system(size: 11))
                  .foregroundStyle(.secondary)
              }
              .padding(.bottom, 2)

              switch selectedTab {
              case .general:
                generalSettingsView
              case .reminders:
                reminderSettingsView
              case .timers:
                timerSettingsView
              }
            }
            // 给滚动条保留空间，切换长短页面时卡片宽度保持一致。
            .frame(width: max(0, geometry.size.width - 64), alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 28)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
          // 等窗口完成首轮布局，避免 AppKit 恢复焦点后又把长页面向下卷动。
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            proxy.scrollTo("contentTop", anchor: .top)
          }
        }
        .onChange(of: selectedTab) { _ in
          proxy.scrollTo("contentTop", anchor: .top)
        }
      }
    }
  }

  var generalSettingsView: some View {
    VStack(spacing: 20) {
      SettingsSection(title: "启动与菜单栏") {
        SettingsRow(
          title: "登录时启动", showsTopDivider: false,
          helpText: "登录 Mac 时自动启动 KLock。"
        ) {
          Toggle("", isOn: $viewModel.startAtLogin)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.startAtLogin, publisher: viewModel.$startAtLogin) { _ in
              viewModel.savePreferences()
            }
        }
        SettingsRow(
          title: "在菜单栏显示下一个计时器",
          helpText: "在菜单栏显示即将结束的计时器，替换原图标。"
        ) {
          Toggle("", isOn: $viewModel.showNextTimerInMenuBar)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.showNextTimerInMenuBar, publisher: viewModel.$showNextTimerInMenuBar) { _ in
              viewModel.savePreferences()
            }
        }
        SettingsRow(
          title: "备用菜单栏图标",
          helpText: "将菜单栏图标换成另一种样式。"
        ) {
          Toggle("", isOn: $viewModel.useAlternativeMenuBarIcon)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.useAlternativeMenuBarIcon, publisher: viewModel.$useAlternativeMenuBarIcon) { _ in
              viewModel.savePreferences()
            }
        }
        SettingsRow(
          title: "自定义菜单栏文字",
          helpText: "用文字替代菜单栏图标。"
        ) {
          Toggle("", isOn: $viewModel.useCustomMenuBarIcon)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.useCustomMenuBarIcon, publisher: viewModel.$useCustomMenuBarIcon) { _ in
              viewModel.savePreferences()
            }
        }
        if viewModel.useCustomMenuBarIcon {
          SettingsRow(
            title: "菜单栏文字",
            helpText: "输入要显示在菜单栏上的文字。"
          ) {
            TextField("输入文字", text: $viewModel.customMenuBarWord)
              .textFieldStyle(RoundedBorderTextFieldStyle())
              .frame(width: 100)
              .onChangeCompat(viewModel.customMenuBarWord, publisher: viewModel.$customMenuBarWord) { _ in
                viewModel.schedulePreferencesSave()
              }
          }
        }
        SettingsRow(
          title: "自定义菜单栏符号",
          helpText: "使用自定义 SF Symbol 作为菜单栏图标。"
        ) {
          Toggle("", isOn: $viewModel.useCustomMenuBarSymbol)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.useCustomMenuBarSymbol, publisher: viewModel.$useCustomMenuBarSymbol) { _ in
              viewModel.savePreferences()
            }
        }
        if viewModel.useCustomMenuBarSymbol {
          SettingsRow(
            title: "自定义符号名称",
            helpText: "输入 SF Symbol 的名称。"
          ) {
            TextField("输入文字", text: $viewModel.customMenuBarSymbol)
              .textFieldStyle(RoundedBorderTextFieldStyle())
              .frame(width: 100)
              .onChangeCompat(viewModel.customMenuBarSymbol, publisher: viewModel.$customMenuBarSymbol) { _ in
                viewModel.schedulePreferencesSave()
              }
          }
        }
      }
      .padding(.top, 10)

      SettingsSection(title: "显示") {
        SettingsRow(
          title: "仅以分钟显示时间", showsTopDivider: false,
          helpText:
            "开启后时间只以分钟显示，不再转换为小时和分钟。"
        ) {
          Toggle("", isOn: $viewModel.viewAsMinutes)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.viewAsMinutes, publisher: viewModel.$viewAsMinutes) { _ in
              viewModel.savePreferences()
            }
        }
        SettingsRow(
          title: "显示拖拽连线",
          helpText:
            "开启后从菜单栏图标到鼠标指针之间显示一条连线。"
        ) {
          Toggle("", isOn: $viewModel.showDragIndicator)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.showDragIndicator, publisher: viewModel.$showDragIndicator) { _ in
              viewModel.savePreferences()
            }
        }
        if viewModel.showDragIndicator {
          HStack {
            SettingsRow(
              title: "自定义连线颜色",
              helpText: "开启后可手动指定连线颜色。"
            ) {
              Toggle("", isOn: $viewModel.changeRubberbandColor)
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
                .frame(width: 40)
                .onChangeCompat(viewModel.changeRubberbandColor, publisher: viewModel.$changeRubberbandColor) { _ in
                  viewModel.savePreferences()
                }
            }
          }
          if viewModel.changeRubberbandColor {
            HStack {
              SettingsRow(
                title: "连线颜色",
                helpText: "选择拖拽连线的颜色。"
              ) {
                ColorPicker("", selection: $viewModel.dragLineColor)
                  .frame(width: 40, alignment: .trailing)
              }
            }
          }
        }

      }
    }
  }

  var reminderSettingsView: some View {
    VStack(spacing: 20) {
      SettingsSection(title: "提醒事项") {
        SettingsRow(
          title: "为什么需要权限",
          subtitle: "授权后可将计时器同步到系统「提醒事项」。不允许时仍可使用应用内提醒卡片，只是不再同步。",
          showsTopDivider: false
        ) {
          EmptyView()
        }
        SettingsRow(
          title: "允许创建提醒事项",
          subtitle: "新建计时器时同步到系统提醒事项"
        ) {
          Toggle("", isOn: Binding(
            get: { viewModel.allowReminders },
            set: { enabled in
              viewModel.allowReminders = enabled
              viewModel.savePreferences()
              if enabled {
                Task {
                  await viewModel.ensureReminderAccessAndFetchLists()
                }
              }
            }
          ))
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
        }
        if let issue = viewModel.reminderAccessIssue {
          SettingsRow(title: "提醒事项权限", subtitle: issue, subtitleColor: .orange) {
            Button("前往设置") {
              viewModel.openReminderSettings()
            }
            .font(.system(size: 12))
          }
        }
        SettingsRow(
          title: "提醒列表",
          helpText: "选择提醒要创建到哪个列表。"
        ) {
          if viewModel.reminderAccessIssue != nil {
            Text("未获完整授权")
              .font(.system(size: 11.5))
              .foregroundStyle(.secondary)
          } else if !viewModel.allowReminders {
            Text("开启后选择提醒列表")
              .font(.system(size: 11.5))
              .foregroundStyle(.secondary)
          } else if viewModel.reminderLists.isEmpty {
            Text("暂无可选列表")
              .font(.system(size: 11.5))
              .foregroundStyle(.secondary)
          } else {
            Picker("", selection: Binding(
              get: { viewModel.selectedList },
              set: { list in
                viewModel.selectedList = list
                viewModel.savePreferences()
              }
            )) {
              ForEach(viewModel.reminderLists, id: \.self) { list in
                Text(list.title).tag(list as EKCalendar?)
              }
            }
            .pickerStyle(MenuPickerStyle())
            .frame(width: 140, alignment: .trailing)
          }
        }
        SettingsRow(
          title: "同步删除提醒",
          helpText:
            "开启后，删除计时器时会一并删除由本应用创建的提醒。"
        ) {
          Toggle("", isOn: $viewModel.deleteReminders)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .disabled(!viewModel.allowReminders)
            .onChangeCompat(viewModel.deleteReminders, publisher: viewModel.$deleteReminders) { _ in
              viewModel.savePreferences()
            }
        }
        SettingsRow(
          title: "忽略短时计时器",
          helpText: "开启后，较短的计时器不会创建提醒。"
        ) {
          Toggle("", isOn: $viewModel.ignoreShortTimers)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .disabled(!viewModel.allowReminders)
            .onChangeCompat(viewModel.ignoreShortTimers, publisher: viewModel.$ignoreShortTimers) { _ in
              viewModel.savePreferences()
            }
        }

        if viewModel.ignoreShortTimers && viewModel.allowReminders {
          HStack {
            Slider(
              value: $viewModel.shortTimerThresholdMinutes,
              in: 1...60,
              step: 1
            )
            .frame(width: 250, alignment: .leading)
            .padding(.bottom, 15)
            .onChangeCompat(viewModel.shortTimerThresholdMinutes, publisher: viewModel.$shortTimerThresholdMinutes) { _ in
              viewModel.savePreferences()
            }
            Text("\(Int(viewModel.shortTimerThresholdMinutes)) 分钟")
              .frame(width: 50, alignment: .trailing)
          }
        }
      }

      SettingsSection(title: "系统通知") {
        SettingsRow(
          title: "通知权限",
          subtitle: "未允许时仍会显示应用内提醒卡片",
          showsTopDivider: false
        ) {
          HStack(spacing: 8) {
            Text(notificationStatusText)
              .font(.system(size: 12))
              .foregroundColor(viewModel.notificationsAuthorized == false ? .orange : .secondary)
            if viewModel.notificationsAuthorized == false {
              Button("去开启") {
                viewModel.openNotificationSettings()
              }
              .font(.system(size: 12))
            }
          }
        }
      }
    }
  }

  var timerSettingsView: some View {
    VStack(spacing: 20) {
      SettingsSection(title: "计时器") {
        SettingsRow(
          title: "自定义计时器名称", showsTopDivider: false,
          helpText:
            "开启后，创建计时器时可以输入自定义名称。"
        ) {
          Toggle("", isOn: $viewModel.allowCustomNames)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.allowCustomNames, publisher: viewModel.$allowCustomNames) { _ in
              viewModel.savePreferences()
            }
        }
        SettingsRow(
            title: "播放闹铃",
            helpText:
              "开启后，计时结束时立即播放闹铃。"
          ) {
            Toggle("", isOn: $viewModel.playAlarmSound)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.playAlarmSound, publisher: viewModel.$playAlarmSound) { _ in
              viewModel.savePreferences()
            }
        }

        if viewModel.playAlarmSound {
          SettingsRow(
            title: "持续播放直到手动停止",
            helpText:
              "循环播放闹铃，并保留已结束的计时器，直到你手动删除它。"
          ) {
            Toggle("", isOn: $viewModel.loopAlarmUntilStopped)
              .toggleStyle(SwitchToggleStyle())
              .labelsHidden()
              .frame(width: 40)
              .onChangeCompat(viewModel.loopAlarmUntilStopped, publisher: viewModel.$loopAlarmUntilStopped) { _ in
                viewModel.savePreferences()
              }
          }

          SettingsRow(
            title: "闹铃音频",
            helpText:
              "从应用自带的 .mp3/.wav 文件中选择一个。"
          ) {
            VStack(alignment: .trailing, spacing: 6) {
              Toggle("使用自定义音频文件", isOn: $viewModel.useCustomAlarmSound)
                .toggleStyle(SwitchToggleStyle())
                .frame(width: 220, alignment: .trailing)
                .onChangeCompat(viewModel.useCustomAlarmSound, publisher: viewModel.$useCustomAlarmSound) { _ in
                  viewModel.savePreferences()
                }

              if viewModel.useCustomAlarmSound {
                HStack {
                  Text(
                    viewModel.customAlarmSoundName.isEmpty
                      ? "未选择文件"
                      : viewModel.customAlarmSoundName
                  )
                  .foregroundColor(.secondary)
                  .lineLimit(1)
                  Button("选择文件…") {
                    isShowingSoundImporter = true
                  }
                }
              } else {
                if viewModel.availableAlarmSounds.isEmpty {
                  Text("未找到音频文件")
                    .foregroundColor(.secondary)
                    .frame(width: 180, alignment: .trailing)
                } else {
                  Picker("", selection: $viewModel.selectedAlarmSound) {
                    ForEach(viewModel.availableAlarmSounds, id: \.self) { sound in
                      Text(viewModel.displayName(for: sound)).tag(sound)
                    }
                  }
                  .pickerStyle(MenuPickerStyle())
                  .frame(width: 180, alignment: .trailing)
                  .onChangeCompat(viewModel.selectedAlarmSound, publisher: viewModel.$selectedAlarmSound) { _ in
                    viewModel.savePreferences()
                  }
                }
              }
            }
          }
        }

        SettingsRow(
          title: "启用 5 分钟模式",
          subtitle: "按住 Control 拖拽，以 5 分钟为步进"
        ) {
          Toggle("", isOn: $viewModel.allowFiveMinuteMode)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.allowFiveMinuteMode, publisher: viewModel.$allowFiveMinuteMode) { _ in
              viewModel.savePreferences()
            }
        }
        SettingsRow(
          title: "启用秒模式",
          subtitle: "按住 Shift 拖拽，以秒为步进"
        ) {
          Toggle("", isOn: $viewModel.allowSecondsMode)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.allowSecondsMode, publisher: viewModel.$allowSecondsMode) { _ in
              viewModel.savePreferences()
            }
        }
      }
      .padding(.bottom, 20)
    }
  }
}


/// 侧栏分页按钮：选中时是强调色的半透明胶囊，悬停有极淡的高光。
private struct SettingsTabButton: View {
  let icon: String
  let label: String
  let isSelected: Bool
  let action: () -> Void

  @Environment(\.colorScheme) private var scheme
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: icon)
          .font(.system(size: 12, weight: .medium))
          .frame(width: 17)
        Text(label)
          .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .foregroundStyle(isSelected ? Color.primary : Color.secondary)
      .padding(.horizontal, 9)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: Glass.sidebarSelectionRadius, style: .continuous)
          .fill(
            isSelected
              ? Glass.selectionFill(scheme)
              : (isHovering ? Color.primary.opacity(0.05) : Color.clear)
          )
      )
      .contentShape(RoundedRectangle(cornerRadius: Glass.sidebarSelectionRadius, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }
}
