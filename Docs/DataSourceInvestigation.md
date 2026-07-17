# Codex Usage 数据源调查

更新日期：2026-07-17（Asia/Shanghai）

## 官方文档结论

OpenAI 当前把 `codex login` 标记为 stable，可用于建立和检查本机 Codex 登录状态。`codex login status` 能确认是否已经通过 ChatGPT 登录，但不会直接返回套餐额度、重置时间或 Credits。

`codex app-server` 仍标记为 experimental。它是 Codex rich client 的本机接口，能够在已登录的本机 Codex 环境中返回 account、rate limits 与 usage 数据；但由于成熟度不是 stable，本应用不能把它描述为公开稳定 API，也不能把它作为唯一数据源。

## 当前生产数据源

### VerifiedOfficialDataSource

保留稳定机器可读接口的扩展位。当前 Codex CLI 没有公开、稳定且机器可读的额度子命令，所以该来源明确返回 unavailable，不调用猜测接口。

### LocalCodexSessionDataSource

用户授权后，应用优先调用 OpenAI 签名的本机 `codex` 命令：

- 先执行 `codex login status` 检查本机 Codex 是否已登录；
- 登录可用时启动本机 `codex app-server --stdio`；
- 读取 `account/read`、`account/rateLimits/read` 与 `account/usage/read`；
- 应用不直接读取 `auth.json`，不保存 Token，不记录 Cookie 或 Authorization；
- 只信任 `/Applications/ChatGPT.app/Contents/Resources/codex` 等 OpenAI 签名 App 内置路径；PATH/custom executable 必须单独授权。

该来源在 UI 中显示为“本机 Codex 登录”。它适合满足用户“复用本机 Codex 登录额度”的需求；若失败、未登录或未授权，仓库会继续尝试官方页面、缓存和估算。

### OfficialWebViewDataSource

回退实时来源为 `https://chatgpt.com/codex/settings/usage` 与同源 Analytics 页面：

- 用户只在应用自己的 WKWebView 中登录；
- 登录会话保存在 WebKit 隔离存储，可在设置中清除；
- 导航只允许 OpenAI/ChatGPT 官方域名；
- 应用代码不读取 Cookie、Authorization 或登录 Token；
- 额度请求使用页面自身同源会话并禁用缓存；
- JSON 端点不可用时只解析用户可见 DOM；无法无歧义识别时失败关闭；
- 页面未登录时，刷新操作直接打开应用内登录窗口。

这是对官方用户页面的本地读取，不应描述为 OpenAI 公开 API。页面结构变化时需要使用最小化、脱敏 Fixture 更新解析器。

### 本机实时 Token

这是独立的本地功能，不参与登录或额度读取。用户授权后只扫描 `~/.codex/sessions` 中结构化 `token_count` 事件的时间戳和累计数值，忽略消息正文、提示词、代码、工具输出和文件路径。

### 缓存与估算

- 缓存只来自先前成功读取的真实快照；超过 60 分钟或额度周期后不作为当前额度展示。
- 本地估算至少需要两个真实快照，只估算主额度短期趋势并显示 `≈`。
- 套餐、Credits、重置次数和缺失模块不会被推测或补零。

## 当前优先级

1. 已验证的稳定官方机器接口（当前不可用）；
2. 本机 Codex 登录；
3. 应用内 OpenAI 官方页面会话；
4. 有效 SwiftData 缓存；
5. 本地历史趋势估算；
6. 明确显示不可用。

Analytics 在额度完成后独立补充，并按模块保留真实来源。任何登录或页面失败都不会导致应用读取 Safari 或 Chrome 的私有认证数据库。
