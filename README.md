# NowKeys

NowKeys 是一个轻量的 macOS 菜单栏媒体控制器。无需切换窗口，就能控制当前正在播放声音的应用。

![NowKeys App Icon](space_playbar/Assets.xcassets/AppIcon.appiconset/NowKeys-256.png)

## 能做什么

- 自动识别 macOS 当前的 Now Playing 应用，并显示真实应用名称和图标
- 在菜单栏直接播放或暂停
- 后退 15 秒、前进 30 秒
- 点击来源名称查看当前标题、作者，并快速打开来源应用
- 适用于支持 macOS 系统媒体控制的小宇宙、浏览器、音乐与播客应用

## 安装

1. 从 [Releases](https://github.com/hnwangjy/nowkeys/releases) 下载最新的 DMG。
2. 打开 DMG，将 **NowKeys** 拖入“应用程序”。
3. 启动 NowKeys，控制条会出现在菜单栏。

> 当前构建已使用 Developer ID 签名，但尚未经过 Apple 公证。首次启动时如果 macOS 阻止打开，请在 Finder 中右键 NowKeys，选择“打开”。

## 使用方式

开始播放任意受支持应用中的内容，NowKeys 会自动显示当前来源。左侧点击应用名称可以查看播放信息；右侧三个按钮分别用于后退、播放/暂停和前进。

NowKeys 调用 macOS 的系统 Now Playing / MediaRemote 能力，不会模拟鼠标点击，也不会为了控制播放而跳转到来源应用。

## 系统要求

- macOS 26.7 或更高版本
- 当前 Release 为 Apple Silicon（arm64）版本

## 开发

使用 Xcode 打开 `space_playbar.xcodeproj` 后运行 `space_playbar` Scheme。项目通过 Swift Package Manager 使用 [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter)。

## 说明

NowKeys 依赖 macOS 的非公开 MediaRemote 接口，因此更适合作为个人工具和开源实验项目；系统升级后相关行为可能发生变化。
