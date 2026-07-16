# 隐私

- 所有历史和普通设置只保存在本机；没有中转服务器、统计 SDK、广告 SDK或遥测上传。
- 登录只发生在官方域名的应用内 WKWebView；应用不提供密码框，不读取其他浏览器 Cookie。
- WebKit 登录态留在应用自身数据存储，可在设置中清除。
- 只有用户未启用本机 Codex，或主动开启“补充工作区 Analytics”时，应用才会加载隐藏的官方页面。页面已加载的额度与 Analytics JSON 会在 WebView 内存中短暂解析，不保存 Cookie、Authorization 响应头或原始响应体；请求直接发往 OpenAI/ChatGPT，不经过开发者服务器。
- 应用不读取 Codex 聊天、会话内容或用户项目代码。
- `SensitiveDataRedactor` 对 Authorization、Cookie、Token、Session ID、Email 和敏感查询参数脱敏。
- 当前实现不自行持久化 Token，因此无需 Keychain。若未来增加非 WebKit 敏感状态，必须使用 Keychain，不能使用 UserDefaults。
- “复用本机 Codex 登录”是需要用户明确授权的实验性功能。授权后，应用启动本机 Codex 官方 `app-server`，读取套餐、额度、聚合 Token 使用和账户使用摘要；不读取对话标题、对话内容、项目代码或提示词。应用不直接打开 `auth.json`，不接收、复制、记录或持久化其中的 Token。撤销授权后该数据源立即停止参与刷新。
- “本机实时今日 Token”需要单独授权。启用后，应用只扫描 `~/.codex/sessions` 中的结构化 `token_count` 事件、累计 Token 数与时间戳，并忽略提示词、代码、工具输出、文件路径和消息正文。该统计仅代表这台 Mac 已落盘的 Codex 活动，不包含其他设备。
- 默认只信任 OpenAI 团队 `2DC432GLL2` 签名的 ChatGPT/Codex 应用内置命令。执行 PATH 或 `CODEX_CLI_PATH` 中的自定义 CLI 必须由用户在高级数据源设置中另行开启。

SwiftData 默认位于应用容器/Application Support 对应目录；Swift Package 开发运行时由系统为 bundle 标识选择本地容器位置。
