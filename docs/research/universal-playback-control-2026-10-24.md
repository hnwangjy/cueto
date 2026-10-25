# Cueto：整台 Mac 多应用独立播放控制调研

日期：2026-10-24

## 目标与判断标准

目标是让 Cueto 成为当前设备的统一播放控制台：发现正在播放和已暂停的音频来源，在同一个面板中分别播放、暂停，其他来源不受影响。应用级入口应能容纳浏览器内的多个独立播放会话。

用户已明确：不以静音替代暂停，不通过模拟鼠标点击播放器页面实现，不把只适配网易云当作完整目标。

本次不修改 Cueto 控制逻辑、不安装扩展、不更改系统权限。以下结论区分官方接口能力、开源项目声明/源码证据、本机实验及仍待验证的假设。

真正满足目标需要同时成立：

1. 能识别目标来源，区分应用、进程与播放会话。
2. 能向选定来源发送命令，而非交给系统最近的 Now Playing 应用。
3. 暂停后媒体进度停止，其他来源继续播放；恢复时从该来源正确位置继续。
4. 读到实际状态或明确的无法确认结果，不能因调用返回成功就认为目标已执行。
5. 对已暂停、后台、多个同时播放的来源仍能工作。

## 调研结论

目前没有查到能够证明“任意音频应用，无需应用配合，均可独立播放/暂停”的 macOS 公开接口或开源实现。这个结论是本次检索与实验的证据边界，不是对所有私有接口的穷尽性证明。

最接近目标的产品组合使用应用脚本、浏览器脚本/扩展、应用 IPC、快捷键等方式。它们能提供统一入口，但支持范围取决于来源暴露的控制能力。Core Audio 能发现或处理输出，不等于拿到了应用内部播放器。

因此，产品可以坚持统一控制目标，技术上应验证多种控制通道是否能形成足够广的覆盖；不能先把所有列表行接到全局媒体命令上，再宣称独立控制。

## 一、Apple 接口能解决什么

| 接口/机制 | 证据支持的能力 | 对本目标的意义 |
| --- | --- | --- |
| Core Audio 进程列表、活动输出属性 | 发现音频进程，判断是否有活动输出流 | 可作为来源发现层；不直接证明正在播放媒体或存在可恢复会话 |
| Core Audio process taps | 捕获指定进程/进程组的音频，可静音原输出 | 可做音量、静音、路由；没有证据表明能停止原应用的媒体时间线 |
| MPRemoteCommandCenter | 应用注册自己的播放命令处理器，接收系统和附件控制 | 不是用于任意第三方应用的公开出站控制器 |
| Now Playing / MediaSession | 发布应用自己的会话、状态和处理命令的回调，申请成为主会话 | 没有找到 Cueto 直接取得其他应用任意会话并控制的公开入口 |
| Scripting Bridge / Apple Events | 给支持脚本的指定应用发送其支持的命令 | 是真正的定向控制，但应用需要提供对应脚本接口 |
| CGEventPostToPid | 把输入事件投递到指定应用进程的事件流 | 可作为更通用的候选通道；目标应用是否处理媒体键、后台是否响应需要逐类实测 |
| Accessibility actions | 请求指定可访问性对象执行它支持的动作 | 可能覆盖一部分有播放菜单/按钮的应用；属于 UI 自动化，不符合当前默认约束，不纳入默认实现 |

来源：

- [Apple：Core Audio 进程列表](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertyprocessobjectlist)
- [Apple：isRunningOutput](https://developer.apple.com/documentation/coreaudio/audiohardwareprocess/isrunningoutput)
- [Apple：Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
- [Apple：MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter)
- [Apple：Handling external player events notifications](https://developer.apple.com/documentation/mediaplayer/handling-external-player-events-notifications)
- [Apple：MediaSession](https://developer.apple.com/documentation/nowplaying/mediasession)
- [Apple：Scripting Bridge](https://developer.apple.com/documentation/scriptingbridge)
- [Apple：CGEventPostToPid](https://developer.apple.com/documentation/coregraphics/cgevent/posttopid(_:))
- [Apple：AXUIElementPerformAction](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction)

本机 macOS SDK 的 CGEvent.h 也明确将 CGEventPostToPid 描述为向指定应用的事件流投递事件。它没有承诺把事件解释为播放器命令。

## 二、现有项目的真实覆盖范围

| 项目 | 是否真的控制播放 | 如何实现与覆盖边界 | 借鉴价值 |
| --- | --- | --- | --- |
| BeardedSpice / Beardie | 是，对支持的播放器和站点 | 原生播放器适配 + 各站点 JavaScript 策略；有明确支持列表 | 来源选择、会话抽象、可扩展策略，而非任意应用通用接口 |
| Conduct | 是，对支持的原生播放器和 YouTube | 原生应用 AppleScript；YouTube 激活窗口后发站点快捷键 | 多后端统一入口；不能据“Universal”宣传词认定全应用覆盖 |
| Mac Media Keys | 是，对可脚本控制或响应相应按键的应用 | AppleScript；失败后按 PID 发空格/方向键 | 定向输入通道；空格依赖焦点和应用快捷键，不能盲目作为通用兜底 |
| Beamhook | 是，对支持的应用/浏览器标签页；另有广泛音量控制 | 应用 AppleScript，浏览器页面脚本；帮助文档明确 Firefox 标签页不支持，只对支持的来源展示播放按钮 | 当前最接近“统一应用和会话面板”的参照，也直接展示了覆盖边界 |
| Background Music | 是，对支持的音乐播放器；另有按应用音量 | 音乐播放器适配与音频混音是两条不同能力 | 不能把广泛音量覆盖当作广泛播放控制覆盖 |
| FineTune | 文档重点是音量、静音、路由、EQ | 音频输出处理 | 是输出控制参考，不能作为独立播放/暂停已解决的证据 |
| FlowSound | 是，对支持的音乐播放器 | Music/Spotify 用 AppleScript，网易云实验适配使用菜单自动化 | 证明网易云可通过 UI 自动化单独控制，但不满足当前默认约束，也不是跨应用通用方案 |
| ungive/media-control | 控制系统当前 Now Playing | 命令行全局媒体控制 | 能复用当前来源控制能力，不能据此认定具备目标应用选择 |

核对入口：

- [BeardedSpice README](https://github.com/beardedspice/beardedspice)：支持的原生应用、浏览器和网站策略说明。
- [Beardie README](https://github.com/vityevato/beardie)：多个已支持播放器与网页来源切换。
- [Conduct README](https://github.com/kxdrsrt/conduct-app)：How It Works 和 YouTube Support。
- [Mac Media Keys 控制源码](https://github.com/rayhatfield/mac-media-keys/blob/main/MacMediaKeys/MediaController.swift)：AppleScript 与 sendKeystrokeToApp。
- [Beamhook 帮助](https://beamhook.app/help/)：Firefox 不支持、页面脚本设置，以及播放按钮只对支持来源出现。
- [Background Music README](https://github.com/kyleneideck/BackgroundMusic)：auto-pause 支持列表和 per-application volume。
- [FineTune README](https://github.com/ronitsingh10/FineTune)：音量、静音、路由与 EQ。
- [FlowSound 控制源码](https://github.com/mattwong05/FlowSound/blob/main/Sources/FlowSound/MusicControlAdapter.swift)：独立的网易云实验适配。
- [ungive/media-control README](https://github.com/ungive/media-control/blob/master/README.md)。

## 三、我们已经测出了什么

### 激活窗口不是切换媒体接收方

Firefox 和网易云的交互实验：只激活网易云，系统媒体目标仍是 Firefox；在网易云手动开始播放后，目标切到网易云；暂停网易云后目标仍被保留。此时将 Firefox 切到前台再按硬件媒体键，用户确认恢复的是网易云。

这些结果解释了 Cueto“显示/选中某个应用，但命令控制上一轮播放来源”的问题。

### 带目标标识的私有接口也未通过当前实验

WebKit 的头文件声明了 MRMediaRemoteSendCommandToApp，参数含 appDisplayID。本机也能解析该符号。但在独立探针中，使用 Firefox 的 bundle identifier、空 origin、appOptions=0：

1. 发送 Firefox 播放，接口返回 accepted=1、error=0、handler status=[0]；Firefox 没有开始输出，网易云继续播放。
2. 在网易云播放、Firefox 暂停时，向 Firefox 发送暂停；系统报告网易云由 playing=true 变为 false。
3. 实验后已恢复网易云播放。

这证明当前这组调用没有实现目标应用选择。不能从“返回成功”推出“指定的应用执行成功”。尚未证明所有 origin/options 组合都不可用，也尚未确认具体权限机制是根因。

- [WebKit 接口声明](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/PAL/pal/spi/mac/MediaRemoteSPI.h)
- [WebKit 测试调用](https://github.com/WebKit/WebKit/blob/main/Tools/TestWebKitAPI/Tests/WebKit/WKWebView/MediaSession.mm)：测试传入空应用目标，不能作为第三方应用定向成功的证据。

### 活动输出流不是可靠的播放状态

实验中网易云暂停后，Core Audio 一度仍报告活动输出流，随后才停止。因此不能仅用 isRunningOutput 来判定暂停是否成功；也不能仅根据它决定播放/暂停切换方向。

## 四、面向全设备覆盖的候选架构

这部分是工程建议，尚未实现或通过完整兼容性测试。

来源发现与命令控制分别建模：

- 应用身份：bundle identifier + 当前进程身份，处理应用退出、重启和辅助进程。
- 会话身份：浏览器的 tab/frame/media element，或播放器暴露的独立会话。不能仅用一个应用名称表示所有播放内容。
- 命令能力：是否支持明确 play、pause、toggle，能否后台控制，是否能回读状态。
- 验证结果：已确认目标状态、命令已发但无法确认、未执行/失败。一次成功不能永久推定所有页面和窗口均支持。

控制通道候选：

1. **应用公开脚本/API/IPC**：可靠地指定来源和明确状态；按能力注册，可复用同类应用协议。
2. **浏览器扩展桥接**：通用扫描 HTML audio/video 元素，按 tab/frame/element 标识精确发送 play/pause。Firefox 与 Chromium 可共享较多 WebExtension 逻辑，Safari 通信/分发需要单独处理。
3. **指定进程媒体键**：独立验证是否能成为原生应用之间的通用补充通道。按键投递成功与播放器响应成功分开记录。
4. **快捷键配置**：只能作为用户明确配置的低保证能力，不能向未知焦点默认发送空格，也不能通过 toggle 保证明确 play 或 pause。
5. **Accessibility 菜单/按钮动作**：只列为备选研究，不在当前约束下自动加入。
6. **系统 Now Playing**：只控制当前系统媒体目标，不承担任意来源路由。

浏览器桥接是覆盖“一类来源”的通用方案，但也不是整个设备通用方案。Web Audio、自定义渲染器、受限制页面、跨域 frame 权限、多个播放器以及恢复播放的自动播放策略都需要单独验证。HTMLMediaElement.play() 返回 Promise，拒绝时应明确反馈，不能假设 Cueto 的一次点击自然满足网页的所有播放权限。

- [Mozilla：Native Messaging](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging)
- [Mozilla：HTMLMediaElement.play](https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/play)
- [Mozilla：HTMLMediaElement.pause](https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/pause)
- [Apple：Safari 扩展与本地应用通信](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)

## 五、下一轮实验：先验证通用性，不先写特例

### 实验 A：按进程投递媒体键

优先级最高，目标是验证它能否成为不依赖每个播放器专用接口的通道。

- 分别投递标准媒体键按下/抬起事件到目标 PID，记录事件发送权限；本轮不以空格键自动兜底。
- 目标应用先在后台，另一个应用保持系统 Now Playing 主目标，排除系统路由恰好一致造成的假成功。
- 做双方向测试：A 播放/B 暂停，以及 A 暂停/B 播放。
- 用目标进度/状态与对照应用状态核验，不能只看 Core Audio 输出流。
- 同时测前台、后台、最小化、文本输入框有焦点、窗口关闭但应用运行等条件。
- 如果事件投递后没有结果，区分权限不足、进程身份错误和目标不处理该事件；不能立即断定 API 对所有应用无效。

### 代表性覆盖矩阵

| 来源类型 | 代表样本 | 必须验证的差异 |
| --- | --- | --- |
| 可脚本原生播放器 | Music，设备有安装时再测 Spotify | 脚本通道对照；后台明确播放/暂停与状态读取 |
| 非脚本播放器 | 网易云、小宇宙 | 指定进程媒体键是否响应；启动/退出与辅助进程识别 |
| Gecko 浏览器 | Firefox 两个不同标签页 | 应用级命令是否能到达；即便到达是否仍只能选浏览器内部最后会话 |
| Chromium 浏览器 | Chrome 两个不同标签页 | 与 Firefox 区分实现，不把一个浏览器结果推广到所有浏览器 |
| 本地播放器 | 设备已安装的 VLC/IINA/mpv | 默认媒体键与可选公开 IPC 对照，不能假定 IPC 已开启 |
| Web Audio / 游戏 / 实时流 | 一个可控测试页面或已有应用 | 是否有媒体级暂停语义，能否读取与恢复；不得以冻结整个进程或静音算成功 |

### 实验 B：浏览器通用桥接最小验证

若实验 A 不能覆盖浏览器，会话级控制转向扩展；先用标准 HTML5 页面、常用视频网站、多个标签页、iframe 页面验证。测试需要同时证明目标停住且其他播放器继续，随后验证暂停后仍能发现并恢复该会话。

### 实验 C：剩余原生应用能力调查

对 A 未覆盖的来源做协议/公开脚本/应用插件能力调查，评估剩余缺口是否能被少数通用机制覆盖。仅为单个应用追加菜单自动化不能算本轮“全设备覆盖”目标已达成。

## 六、决策门槛

- 当前可以继续做实验 A；它尚未在本机测试，不能提前承诺媒体键定向一定有效。
- 若 A 覆盖较广、B 覆盖主流网页媒体，可以实现统一面板加多个控制通道，并公开实测覆盖矩阵。
- 如果严格要求“任意应用、无需应用/扩展配合、无 UI 自动化、均能独立真正暂停”，当前证据尚没有支持这一承诺的路径。
- 应用具备音频输出，并不意味着存在可由外部恢复的播放器；实时通话、游戏和自定义音频引擎必须按实际控制语义评估。
- 当前失败的全局控制实验不作为定向控制发布；能力不明确时明确反馈，不误控另一来源。

本次交付是调研与实验设计，不将任何候选方案标记为已经完成产品功能。
