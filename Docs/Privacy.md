# 隐私

- 所有历史和普通设置只保存在本机；没有中转服务器、统计 SDK、广告 SDK或遥测上传。
- 登录只发生在官方域名的应用内 WKWebView；应用不提供密码框，不读取其他浏览器 Cookie。
- WebKit 登录态留在应用自身数据存储，可在设置中清除。
- 应用启动后恢复隔离的官方页面会话，用于额度与 Analytics。JSON 只在 WebView 内存中短暂解析，不保存 Cookie、Authorization 响应头或原始响应体；请求直接发往 OpenAI/ChatGPT，不经过开发者服务器。
- “本机 Codex 登录”需要单独授权。启用后，应用只调用 OpenAI 签名的本机 `codex` 命令，通过 `codex login status` 与本机 app-server 获取额度；应用不直接读取 `~/.codex/auth.json`，不保存 Token，也不把登录信息写入日志。
- 应用不读取 Codex 聊天、会话内容或用户项目代码。
- `SensitiveDataRedactor` 对 Authorization、Cookie、Token、Session ID、Email 和敏感查询参数脱敏。
- 当前实现不自行持久化 Token，因此无需 Keychain。若未来增加非 WebKit 敏感状态，必须使用 Keychain，不能使用 UserDefaults。
- “本机实时今日 Token”需要单独授权。启用后，应用只扫描 `~/.codex/sessions` 中的结构化 `token_count` 事件、累计 Token 数与时间戳，并忽略提示词、代码、工具输出、文件路径和消息正文。该统计仅代表这台 Mac 已落盘的 Codex 活动，不包含其他设备。

SwiftData 默认位于应用容器/Application Support 对应目录；Swift Package 开发运行时由系统为 bundle 标识选择本地容器位置。
