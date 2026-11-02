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
  @State private var hoverStates: [PreferenceTab: Bool] = [:]
  @State private var isShowingSoundImporter: Bool = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        ForEach(
          [
            (tab: PreferenceTab.general, icon: "gearshape", label: "通用"),
            (
              tab: PreferenceTab.reminders, icon: "bell.fill",
              label: "提醒"
            ),
            (tab: PreferenceTab.timers, icon: "timer", label: "计时器"),
          ], id: \.tab
        ) { tabInfo in
          Button {
            selectedTab = tabInfo.tab
          } label: {
            ZStack {
              Color.clear
                .contentShape(Rectangle())
                .overlay(
                  Group {
                    if hoverStates[tabInfo.tab] ?? false {
                      Color.gray.opacity(0.1)
                    } else if selectedTab == tabInfo.tab {
                      Color.blue.opacity(0.2)
                    } else {
                      Color.clear
                    }
                  }
                )

              VStack(spacing: 4) {
                Image(systemName: tabInfo.icon)
                  .font(.system(size: 16))
                Text(tabInfo.label)
                  .font(.system(size: 10))
              }
              .padding(.vertical, 8)
            }
            .frame(height: 50)
            .frame(minWidth: 60)
            .foregroundColor(selectedTab == tabInfo.tab ? .blue : .gray)
          }
          .buttonStyle(BorderlessButtonStyle())
          .cornerRadius(8)
          .onHover { hover in
            hoverStates[tabInfo.tab] = hover
          }
        }
      }
      .padding(.horizontal)
      .padding(.top)
      ScrollView {
        VStack {
          switch selectedTab {
          case .general:
            generalSettingsView
          case .reminders:
            reminderSettingsView
          case .timers:
            timerSettingsView
          }
        }
        .padding()
      }
    }
    .onAppear {
      viewModel.loadPreferences()
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
    .onChangeCompat(viewModel.allowReminders, publisher: viewModel.$allowReminders) { newValue in
      if newValue {
        Task {
          await viewModel.ensureReminderAccess()
        }
      }
    }
  }

  var generalSettingsView: some View {
    VStack(spacing: 20) {
      SettingsSection(title: "通用") {
        SettingsRow(
          title: "登录时启动",
          helpText: "登录 Mac 时自动启动 Dropclock。"
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
            title: "自定义菜单栏文字",
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
          title: "仅以分钟显示时间",
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
          title: "允许创建提醒事项",
          helpText:
            "开启后，每个新建的计时器都会在「提醒事项」中创建一条提醒。受提醒事项机制限制，时间会向上取整到整分钟。"
        ) {
          Toggle("", isOn: $viewModel.allowReminders)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.allowReminders, publisher: viewModel.$allowReminders) { _ in
              viewModel.savePreferences()
            }
        }

        Divider()

        SettingsRow(
          title: "提醒列表",
          helpText: "选择提醒要创建到哪个列表。"
        ) {
          Picker("", selection: $viewModel.selectedList) {
            ForEach(viewModel.reminderLists, id: \.self) { list in
              Text(list.title).tag(list as EKCalendar?)
            }
          }
          .pickerStyle(MenuPickerStyle())
          .frame(width: 140, alignment: .trailing)
          .disabled(!viewModel.allowReminders)
          .onChangeCompat(viewModel.$selectedList) { _ in
            viewModel.savePreferences()
          }
        }

        Divider()

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

        Divider()

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
    }
  }

  var timerSettingsView: some View {
    VStack(spacing: 20) {
      SettingsSection(title: "计时器") {
        SettingsRow(
          title: "自定义计时器名称",
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

        Divider()

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

          Divider()
        }

        SettingsRow(
          title: "启用 5 分钟模式",
          helpText:
            "开启后，按住 Control 拖拽将以 5 分钟为步进。"
        ) {
          Toggle("", isOn: $viewModel.allowFiveMinuteMode)
            .toggleStyle(SwitchToggleStyle())
            .labelsHidden()
            .frame(width: 40)
            .onChangeCompat(viewModel.allowFiveMinuteMode, publisher: viewModel.$allowFiveMinuteMode) { _ in
              viewModel.savePreferences()
            }
        }

        Divider()

        SettingsRow(
          title: "启用秒模式",
          helpText:
            "开启后，按住 Shift 拖拽仅以秒为步进。"
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
