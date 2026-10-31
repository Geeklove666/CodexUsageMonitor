# Token League

托管地址：<https://codex-token-league.russetwolf8.chatgpt.site>

软件完整面板的“排行榜”内嵌网页；“设置 → 排行榜”连接设备、控制自动同步和断开设备。网页也可直接在浏览器访问。Plus 用户可使用 ChatGPT 账号登录，登录只确认身份，无法验证 Plus 订阅。

## 使用流程

1. 打开软件的排行榜设置，选择“登录并连接排行榜”，确认本机计数读取与上传用途。
2. 在浏览器中使用 ChatGPT 登录，填写 3–24 位英文字母、数字或下划线公开 ID，勾选自愿公开参与并保存。
3. 核对软件显示的连接码，确认连接这台 Mac。连接码 10 分钟内有效，一次性使用。
4. 软件完成授权后开启同步，首次上传最近 7 天真实计数，之后在刷新时最多每 5 分钟上传一次。记录缺失时不制造零值，也不上传 Credits 估算。

关闭自动同步停止后续上传；断开设备移除本机凭据并尽力撤销服务器授权。网页“退出榜单”立即隐藏历史排名并撤销全部设备。退出仅隐藏数据，重新加入时已有计数可再次展示。

## 统计规则

- 有效 Token = 总 Token − 缓存输入 Token，仅统计这台 Mac 的结构化 Codex 用量记录。
- 日榜、周榜、月榜均按北京时间 UTC+8；自然周从周一开始，自然月从每月 1 日开始。
- 每个账号每天保留最大累计值，重复或延迟上传不会重复相加。同用量并列排名，公开前 100 名。
- 月榜按当月已同步记录累计；首次接入最多回补 7 天，因此不会自动补全整月历史。后续需保持同步才能积累完整记录。
- 每个账号同时只有一台上传设备；新连接撤销旧设备。不同设备的统计不会求和。
- 数据由客户端自报，未进行官方认证或防篡改证明，不代表 Plus 套餐额度或作品质量。

## 身份与数据边界

使用 Sites 内置 `/signin-with-chatgpt` 登录及可信服务端身份头，业务不接收用户的 OpenAI OAuth 凭据，不保存邮箱。公开 ID 大小写归一为小写、全站唯一，保留官方名称避免冒充。

设备连接将浏览器身份与软件分开：一次性设备码换取独立的 90 天同步凭据。本机仅在 Keychain 保存凭据，服务器只保存 SHA-256 摘要。匿名读取榜单；修改资料、批准设备、隐藏排名要求浏览器登录及同源请求；上传要求有效设备凭据及公开参与状态。只传输日期、Token 数和固定口径标识，不传输提示词、代码、文件路径、邮箱或 OpenAI 认证凭据。

## API

| 路径 | 用途 |
| --- | --- |
| `GET /api/leaderboard?period=day\|week\|month` | 公开榜单、周期边界与汇总 |
| `GET /api/session` | 当前站点用户的资料及设备 |
| `POST /api/profile` | 登录用户设置公开 ID、参与状态 |
| `POST /api/device/start` | 软件创建 10 分钟连接码 |
| `GET /api/device/preview?code=…` | 登录用户核对设备 |
| `POST /api/device/approve` | 登录用户批准连接 |
| `POST /api/device/token` | 软件轮询、一次性换取设备凭据 |
| `POST /api/usage` | 设备上传日累计值，按日期取最大值 |
| `POST /api/device/revoke` | 登录用户撤销指定设备 |
| `POST /api/device/disconnect` | 软件撤销自身凭据 |
| `POST /api/withdraw` | 隐藏用户并撤销全部设备 |

上传协议示例：

```json
{"source":"codex-local-effective-v1","days":[{"date":"2026-10-30","tokens":12345}]}
```

请求体最大 16 KB，最多 32 天，每日计数必须是 0–1000 亿的整数。连接、轮询、同步有限流。服务端不信任客户端账号字段，始终从浏览器身份或设备凭据确定所属用户。

## 源码与部署

网页源码位于工作区 `Leaderboard/`，使用 Vinext、Cloudflare Workers 和 D1，拥有独立的 Sites 源码仓库；主软件仓库忽略该嵌套仓库，避免错误创建 submodule。[网站源码快照](TokenLeague-source.zip) 对应已部署的源码提交 `23fe9b7a282c83e8ed8cf7febcaed1ef06a39b5a`，包含依赖锁文件、数据库迁移和测试，不包含凭据、数据库内容或构建缓存。站点身份保存在 `Leaderboard/.openai/hosting.json`，维护现有站点应沿用既有 project ID；部署自己的副本则先注册新站点并替换该 ID。SQL 迁移位于网页源码 `drizzle/`。

网页检查：`node --test tests/rules.test.mjs`、`tsc --noEmit`。本机预览可运行 `node tests/api-smoke.mjs` 检查模拟登录、连接码、上传、三种周期和退出行为；此脚本拒绝对生产域名执行，不会在正式榜单写入测试数据。

软件回归测试位于 `Tests/CodexUsageMonitorTests/LeaderboardTests.swift`，覆盖最小上传字段、缺失与零值区分、北京时间分桶和真实日志扫描。正式软件包仍应使用完整 Xcode 工具链运行 `swift test` 并构建验证。
