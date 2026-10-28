# macOS 27.2 Music 控制兼容修复

> 修订：用户指出更像外层状态栏吞掉内部按钮点击。上一轮原生 Music 控制方案已从源码撤回，旧的 `Cueto-macOS27.2-control-test.zip` 不用于本轮验证。以下原生通道记录仅作为已撤回方案的历史；当前修复见文末。

## 录屏证据与判断

用户录屏中，来源面板和右键菜单可以打开；Music 窗口保持在同一首歌的暂停状态。由此不能认定所有菜单栏点击均未送达。原有播放命令通过 mediaremote-adapter 调用私有 `MRMediaRemoteSendCommand`，并在发出后乐观改变图标；远端命令没有实际生效的可能性比完全丢失点击更符合录屏，但未取得远端日志，具体系统根因仍未证实。

## 修改

- 来源是 `com.apple.Music` 时，通过 Music 的公开 AppleScript 字典直接发出 play、pause、previous track、next track，不激活 Music 窗口，不模拟鼠标或键盘，不重复发送全局命令。
- 串行后台执行，2 秒 Apple Events 超时；收到 Music 实际状态后再更改播放图标。成功控制后每秒读取状态，并短期优先采用确认结果，避免旧 MediaRemote 状态覆盖。
- 请求序号校验快速点击的迟到回调，来源切换后不应用旧 Music 命令结果。
- 第一次点击前不启动新的原生状态轮询，避免仅打开 Cueto 就额外触发控制授权；权限拒绝及超时在面板显示原因。
- 子按钮明确接受 inactive-window 的首次点击。其他来源继续使用现有控制及多音源切换路径。

## 验证

- 本机 macOS 26.7.1，不能据此声称 macOS 27.2 已完成实机验收。
- `Tests/AppleMusicTransportScriptTests.swift`：五种脚本（只读、播放、暂停、上一首、下一首）全部可对当前 Music 字典编译；测试未执行媒体命令。
- Debug 构建通过；Release arm64、x86_64 通用构建通过。
- Developer ID 签名完整性校验通过，具备 Apple Events entitlement，无 get-task-allow；测试 ZIP 完整性校验通过。
- 测试包：`dist/testing/Cueto-macOS27.2-control-test.zip`。包含当前未发布代码，版本号未变，不是正式发布，也未上传 GitHub。

27.2 设备需先退出旧 Cueto，再运行测试包中的应用；如系统请求自动化权限，由用户允许控制 Music。复测菜单栏播放、暂停和切歌；如果失败，打开面板记录具体错误。当前尚未确认该设备的实机控制结果。

## 当前方案：状态栏事件接收与区域分发

- 不再给主要控制栏设置 `NSStatusItem.view`。保留系统 `NSStatusBarButton`，注册明确的 target/action 和左／右鼠标事件。
- 视觉内容作为原生按钮的子视图，pointer hit-test 返回 nil，由原生按钮统一接收点击；内部来源／后退／播放／前进按钮通过实际点击位置分发，继续调用原来的控制方法。
- 按实际布局计算横向区域，并覆盖整个菜单栏高度，避免点击图标上下留白落到外层。名称宽度、数量标记及空闲布局改变时重新使用实际 frame。
- 如果转发事件不属于状态栏窗口，则先把屏幕鼠标位置转换到当前窗口坐标，避免直接套用另一窗口的局部坐标。键盘激活仍打开来源面板，右键仍显示上下文菜单。
- `MenuBarInput` 统一日志记录命中的 source／backward／playPause／forward，不记录节目名或歌词。可以区分点击没分发和命令未生效。
- 已删除上一轮 AppleMusicTransport 和相关状态轮询，保留原 MediaRemote 命令与已有多音源逻辑，避免同时改动两条路径导致无法归因。
- `Tests/StatusBarHitRegionsTests.swift` 覆盖 3 种宽度、3 种高度、控制区域顶部／中间／底部、按钮间隙边界、空闲与越界点击，全部通过。Debug 构建通过。27.2 实际鼠标点击仍待设备复测。
