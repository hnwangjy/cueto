# Apple Music 授权与发布检查

2026-10-28，对当前 Git 工作区及所有可达历史文件对象进行检查，未发现硬编码的用户登录令牌、JWT、GitHub 凭据或私钥；发现的是请求接口、授权流程和公开 Sparkle 验证公钥。公钥不是签名私钥。

用户的 Apple Music 登录会话由 WebKit 保存于工程外的应用数据目录；开发版路径为 `~/Library/WebKit/com.wangjiayuan.cueto.dev`。Cueto 不导出 Cookie、用户令牌或密码，不生成工程内的授权文件。该目录不属于 Git 工作区，也不是 Xcode 资源输入。本次不读取、复制或上传该目录的数据，也不清除用户已有登录。

1.2.2 默认不定义 `CUETO_APPLE_MUSIC_LYRICS`。网页登录实现被编译排除，歌词监视器使用不读取旧偏好、不启动定时器、网络监视或 WebKit 的停用实现。设置入口被编译隐藏，旧开发版保存的开关也不会重新开启功能。小宇宙字幕及媒体控制保持可用。

发布只包含经过检查的源文件、发布说明和 Xcode 生成的 `.app`；不提交 `xcuserdata`、本地测试包、日志、网页数据或签名私钥。新增忽略规则覆盖常见私钥、Cookie、WebKit、环境变量及本地授权文件。

发布前再次检查待提交内容、应用资源和最终 DMG；此说明是当前检查结果，不构成对未来任意修改的保证。

最终检查：Release 为 1.2.2（14）、bundle ID `com.wangjiayuan.cueto`，同时包含 arm64 和 x86_64。二进制不含 AppleMusicDirectProbe 类，也未链接 WebKit 或 MusicKit。挂载最终 DMG 后扫描其中 71 个应用文件，未发现登录数据文件、JWT 或私钥字面量。Developer ID 签名完整性、DMG 校验及与应用内公钥对应的 Sparkle 更新签名均通过。

实际重启开发构建，原先已开启 Apple Music 歌词的本机偏好仍在，但设置页不再显示该入口，版本为 1.2.2（14）；小宇宙字幕和灵动岛入口正常显示。未清除本机已有授权数据。
