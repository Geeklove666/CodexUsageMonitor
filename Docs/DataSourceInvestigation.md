# Codex Usage 数据源调查

调查日期：2026-07-15（Asia/Shanghai）

## 环境

- macOS 27.0（Build 26A5378n，Apple Silicon）
- Swift 6.4
- Codex CLI `0.144.2`，路径为 ChatGPT.app 内置 CLI
- `codex login status`：已通过 ChatGPT 登录
- Codex Desktop 相关进程正在运行；进程存在仅用于刷新调度，不代表正在消耗额度
- 后续已安装 Xcode 27 beta 3（27A5218g，macOS 27 SDK）；系统全局开发目录仍保留稳定版 Xcode，项目命令显式使用 `DEVELOPER_DIR`

## 已验证结论

### VerifiedOfficialDataSource

`codex --help` 与子命令列表中没有机器可读的 `status`、`usage`、`limit` 或 `quota` 命令。`/status` 属于交互会话能力，不是可供本应用稳定调用的 CLI 子命令。本机 Codex SQLite 元数据结构中也未发现明确的 usage/quota 表或字段。

因此此数据源当前返回 unavailable，不调用推测接口，不读取聊天、会话或项目内容。它不是当前可用数据源。

### LocalCodexSessionDataSource（实验性、需用户授权）

Codex 官方 `app-server` 提供 `account/read`、`account/rateLimits/read` 与实验性的 `account/usage/read` JSON-RPC 方法，并由 Codex 自身负责读取和刷新登录凭据。实测发现持久登录会话需先调用 `account/read(refreshToken: true)`，否则用量读取可能超时。应用在用户主动授权后执行该刷新，再读取账号类型、套餐、额度窗口、每日 Token 桶和账户使用摘要，不直接读取 `~/.codex/auth.json`，也不接收 Token。

Codex CLI 0.144.2 的本机用量响应已验证包含：`lifetimeTokens`、`peakDailyTokens`、`longestRunningTurnSec`、`currentStreakDays`、`longestStreakDays` 和 `dailyUsageBuckets`。应用仅保留最近 30 个自然日的每日桶。该响应不包含线程数、轮次数、Skills/Plugins 排行、产品入口或 Token 输入/输出构成，因此这些字段只由官方分析页面实际返回时补充，不能用本地资源清单或会话文件推断。

此数据源优先于网页登录额度；未授权、未找到支持 `app-server` 的 Codex、非 ChatGPT 登录或调用失败时自动回退到官方页面。额度读取成功后仍会独立尝试合并官方页面 Analytics，不再因额度源短路而丢失 Token、线程、Skills 等真实分析。由于 `app-server` 与相关接口仍可能变化，界面明确标注为实验性。

### OfficialWebViewDataSource

验证地址：`https://chatgpt.com/codex/settings/usage`。在一个独立、未登录的浏览会话中访问会跳转至 `https://chatgpt.com/` 登录界面。由此确认：

- 页面依赖登录态；
- WKWebView 可以加载官方站点，但用户必须在应用自己的 WebView 中登录；
- 登录态可由应用独立的 `WKWebsiteDataStore` 保存和清除；
- 应用不需要、也不得读取 Safari/Chrome/Codex Desktop 的 Cookie；
- 本次没有登录到该独立会话，因此未能验证登录后页面的额度字段、动态网络请求、Credits、周期名称和重置字段；
- 没有观察、复制或记录 Authorization、Cookie、Token 或响应正文。

该路径属于“官方页面读取”，不是公开 API。生产实现只允许 OpenAI/ChatGPT 官方域名，优先读取用户可见 DOM；当前解析器仅识别明确的“百分比 + remaining/剩余”文本，无法无歧义识别时失败关闭并报告页面结构变化。

### 本地文件

只检查了配置目录的文件名、数据库 schema 元数据和与额度相关的字段名；没有读取聊天内容、代码内容、会话记录或认证文件内容。未发现稳定、明确、可机器读取的当前额度记录。Codex Desktop 的应用支持目录包含浏览器型 Cookie/登录数据库；出于隐私要求，本应用明确不读取它们。

### 缓存与估算

- 缓存只来自本应用先前成功读取的真实快照；超过 60 分钟或超过额度周期后不作为当前额度展示。
- 本地估算至少需要两个真实快照，只估算主窗口的短期趋势，标记为“本地估算”并使用 `≈`。
- Credits、套餐上限、官方周期名称不会凭空估算。

## 字段、稳定性与风险

| 数据源 | 当前可得字段 | 稳定性 | 隐私风险 | 公开 API |
|---|---|---|---|---|
| 官方 CLI/本地状态 | 无已验证额度字段 | 高（明确不可用） | 低，只读能力调查 | 否 |
| 本机 Codex app-server | 用户授权后可读取主/次额度、重置时间、套餐、每日/累计 Token 与账户使用摘要 | 中，随 Codex 版本演进 | 低，Token 由 Codex 自身管理 | 官方本机接口（实验性） |
| 官方 Usage 页面 | 登录后页面当前未完成字段验证；实现可返回无歧义的剩余百分比 | 中低，页面结构会变化 | 中，登录态由 WebKit 本地保存 | 否 |
| 本应用缓存 | 成功快照中的原字段 | 中，有严格过期规则 | 低，本机 SwiftData | 不适用 |
| 本地估算 | 有足够历史时的短期主额度趋势 | 低 | 低，本机计算 | 不适用 |

## 当前无法确认

- 登录后是否显示两个额度窗口、Credits、重置时间及套餐名称；
- 页面数据来自 HTML、内嵌状态还是页面自身的动态请求；
- 动态请求地址、方法、字段、短期 Token 依赖与反自动化策略；
- 官方额度周期的准确名称。

这些内容在未实际观察用户自己的独立 WKWebView 登录会话前不得写入生产字段映射。

## 建议生产方案与维护

额度维持优先级：已验证官方方式 → 用户授权的本机 Codex app-server → 应用自有 WKWebView 官方页面 → 有效持久化缓存 → 本地估算 → 不可用。Analytics 作为独立来源按实际返回模块合并，缺失模块保持未知而不是 0。页面变化时，用用户自愿提供且已脱敏的本地 Fixture 更新解析器和回归测试；不要把内部网页请求升级为“公开 API”，不要记录完整响应或请求头。
