# Cueto

Cueto 是一个轻量的 macOS 菜单栏媒体控制器。它把播放指令准确交给当前正在发声的应用，让你无需切换窗口就能控制小宇宙、浏览器、音乐或播客。

![Cueto App Icon](space_playbar/Assets.xcassets/AppIcon.appiconset/Cueto-256.png)

## 能做什么

- 自动识别 macOS 当前的 Now Playing 应用，并显示真实应用名称和图标
- 在菜单栏直接播放或暂停
- 后退 15 秒、前进 30 秒
- 点击来源名称查看当前标题、作者、实时播放进度、总时长与剩余时长，并打开 Cueto 设置
- 可选择登录 Mac 时自动启动，并可随时开启或关闭自动检查更新
- 可在 Cueto 设置中隐藏指定应用，让它们不出现在控制栏、来源数量和播放来源列表中
- 支持手动立即检查新版本
- 适用于支持 macOS 系统媒体控制的小宇宙、浏览器、音乐与播客应用

## 安装

1. 从 [Releases](https://github.com/hnwangjy/cueto/releases) 下载最新的 DMG。
2. 打开 DMG，将 **Cueto** 拖入“应用程序”。
3. 启动 Cueto，控制条会出现在菜单栏。

> 首次启动时如果 macOS 阻止打开，请在 Finder 中右键 Cueto，选择“打开”。

## 使用方式

开始播放任意受支持应用中的内容，Cueto 会自动显示当前来源。左侧点击应用名称可以查看播放信息；右侧三个按钮分别用于后退、播放/暂停和前进。

在播放信息面板或菜单栏右键菜单中选择“打开 Cueto”，可以管理“登录时自动启动”“自动检查更新”和“隐藏应用”，也可以立即检查新版本。隐藏应用可从当前运行的应用中勾选，或通过“添加应用…”选择未运行的 `.app`。

Cueto 调用 macOS 的系统 Now Playing / MediaRemote 能力，不会模拟鼠标点击，也不会为了控制播放而跳转到来源应用。

## 系统要求

- macOS 26.7 或更高版本
- 当前 Release 为 Apple Silicon（arm64）版本

## 开发

使用 Xcode 打开 `space_playbar.xcodeproj` 后运行 `space_playbar` Scheme。项目通过 Swift Package Manager 使用 [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter) 和 [Sparkle](https://sparkle-project.org/)。

## 说明

Cueto 依赖 macOS 的非公开 MediaRemote 接口，因此更适合作为个人工具和开源实验项目；系统升级后相关行为可能发生变化。
