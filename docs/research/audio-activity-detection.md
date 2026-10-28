# 音频活动判断

Core Audio 的 `kAudioProcessPropertyIsRunningOutput` 表示进程有正在运行的输出 IO，不代表输出样本有可听音量。Firefox 暂停网页后仍可能保持此标记。

控制栏来源和数量使用 `AudioActivityPolicy`：

- 已收到的媒体暂停状态优先于输出 IO，暂停来源不计入播放数量。
- Firefox 等浏览器仅有输出 IO 时，不自动成为播放来源；需收到该应用的媒体播放状态。
- 已发现的进程仍保留在面板中，支持“前往”。仅有 IO 活动时显示“音频流活跃”，不声称正在发声。
- 其他应用保留输出 IO 回退，以兼容多个原生播放器同时播放时的切换。

这是保守的播放状态筛选，不是音量测量。浏览器没有向系统报告媒体会话时，可能不会被自动选中；系统报告播放但内容本身静音时，仍可能显示播放。精确判断数字静音需要另行实现音频采样及阈值策略。

验证：

```sh
swiftc space_playbar/AudioActivityPolicy.swift Tests/AudioActivityPolicyTests.swift -o /tmp/cueto-audio-policy-tests
/tmp/cueto-audio-policy-tests
```

覆盖浏览器仅 IO 活动、确认播放、明确暂停、原生应用回退、进程退出和输出停止。
