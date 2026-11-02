# Dropclock — 菜单栏里随手就有的计时器

[![License: GPL3](https://img.shields.io/badge/license-%20%20GNU%20GPLv3%20-green?style=plastic)](https://opensource.org/license/gpl-3-0) [![GitHub Releases](https://img.shields.io/github/v/release/wrkx/Dropclock)](https://github.com/wrkx/Dropclock/releases/latest)

**Dropclock** 是一款轻量、直观的 macOS 计时器应用，目标是让「创建一个计时器」这件事尽可能快、尽可能顺手。不用再面对繁琐的界面——直接从菜单栏图标往外拖，拖到多长就设多久，松手即开始。免费、开源，并且尽可能极简。

> 本仓库是 [WrkX/Dropclock](https://github.com/WrkX/Dropclock) 的简体中文汉化版本，界面文案已全部译为中文。

![SCR-20250224-irpf](https://github.com/user-attachments/assets/7f2a31da-4fb4-481d-94fe-d426dbcbfc70)

## 主要特性

* **拖拽即创建：** 最符合直觉的计时方式。按住菜单栏图标往外拖，拖动距离就是计时时长，松手开始计时。
* **常驻菜单栏：** 随时可用，一次点击加一次拖拽就能起一个计时器。
* **可选的提醒事项同步：** 可以把计时器同步到 macOS「提醒事项」，即使离开应用也能收到通知。再也不会错过截止时间或煮饭时间。
* **免费开源：** 完全免费、开源，欢迎参与共建。

## 安装

1. 从 [Releases 页面](https://github.com/wrkx/Dropclock/releases/latest) 下载最新的 DMG 文件。
2. 打开下载好的 DMG。
3. 把 Dropclock 图标拖进「应用程序」文件夹。
4. 从「应用程序」中运行 Dropclock，图标会出现在菜单栏。

> 汉化版需自行用 Xcode 打开 `Dropclock.xcodeproj` 编译运行（本机需安装 Xcode，系统要求 macOS 13.0 及以上）。

## 使用说明

1. 在菜单栏找到 Dropclock 图标。
2. **按住图标往外拖。** 拖动过程中会实时显示计时时长，鼠标和图标之间有一条连线。
3. **拖到你想要的时长后松开鼠标**，计时自动开始。
4. **（可选）在偏好设置里开启提醒事项同步。** 右键点击菜单栏图标，选择「偏好设置…」。

### 拖动时长对照

| 操作 | 效果 |
| --- | --- |
| 普通拖拽 | 50 pt 起算，短距离按秒递增；80 pt 后按 30 秒递增；130 pt 后按分钟递增 |
| 按住 `Shift` 拖拽 | 仅以秒为步进（需在偏好设置中启用「秒模式」） |
| 按住 `Control` 拖拽 | 以 5 分钟为步进（需在偏好设置中启用「5 分钟模式」） |

## 参与贡献

Dropclock 是开源项目，欢迎社区贡献。如果你有改进想法、缺陷修复或新功能建议，可以：

* **Fork 本仓库**并提交 Pull Request。
* **提交 Issue** 反馈缺陷或提出功能需求。

## 许可证

Dropclock 基于 [GPL3 许可证](LICENSE) 发布，详见 `LICENSE` 文件。

## 下载

[在此下载最新版本的 Dropclock](https://github.com/wrkx/Dropclock/releases/latest)

-----

**祝你用得顺手！** 如果觉得有帮助，欢迎给原作者的仓库点个星 ✨
