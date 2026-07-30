# 架构

应用采用 SwiftUI + Swift Concurrency + SwiftData。Domain 定义额度、Analytics、仓库、实时 Token 与历史写入边界；Data 对额度按“已验证官方方式 / 本机 Codex 登录 / 应用内 OpenAI 官方页面 / 持久化缓存 / 本地估算”顺序降级，再独立补充本机 Codex 与官方页面 Analytics；Business 保存纯刷新策略；Services 负责编排、网络、持久化管线、通知与重置检测；Features 只消费合并后的统一快照，不直接联网、解析页面或写入历史。

`DefaultCodexUsageRepository` 串行选择数据源，实时请求允许最长 20 秒。本机 Codex 源先通过 `codex login status` 确认登录，再调用 OpenAI 签名的 `codex app-server --stdio` 读取额度；失败时继续回退到官方页面。`WebViewSession` 使用应用自己的持久 WebKit 数据存储，仅允许 OpenAI 官方域名；额度请求带 `no-store`，JSON 不可用时退回可见 DOM 解析。`UsageMonitoringService` 只负责单飞刷新与任务生命周期，通过仓库协议和实时 Token 协议取数；`RefreshPolicy` 负责自动间隔、失败退避与菜单打开判定；`UsageSnapshotPipeline` 统一历史保存、重置判断与通知。额度读取时并发补充已授权的本机实时 Token，额度完成后再由独立任务补充 Analytics。活动/空闲间隔为 60/300 秒，连续失败按 1/2/5/10/30 分钟退避并加入 5% 抖动。倒计时使用本地时间刷新，不触发网络请求。

WebKit 采用按需创建：本机 Codex 或其他前置来源成功时，后台不会初始化官方网页；只有额度链路实际回退到网页或用户主动打开登录窗口时才创建和加载。相同登录页面的并发打开会合并，只有用户点击“重新加载”才强制重新导航。菜单栏额度变化通过快照回调立即同步，倒计时时钟按 30 秒校正且仅在显示文本变化时重绘。`AppLifecycleCoordinator` 在系统睡眠时停止自动刷新与重置定时任务，唤醒后恢复循环并发起一次可合并刷新。

界面在 macOS 26/27 使用 SwiftUI 原生 Liquid Glass；macOS 15 使用系统 Material 回退。Glass 只用于导航与交互层，数据卡片使用标准材质，以维持清晰的内容层级和辅助功能对比度。

完整面板按页面编排、展示组件和展示模型分文件维护；历史读取由独立的 `DashboardHistoryModel` 驱动。本机 Codex 链路按数据源编排、`app-server` stdio 客户端和响应解析拆分，进程控制与 JSON 数据模型不再与授权/UI 状态混放。拆分保持类型为模块内部可见，避免形成额外公共 API。

缓存从 SwiftData 最近真实快照恢复，并持续为估算器提供历史。缓存新鲜度：5 分钟内新鲜、15 分钟内可用缓存、60 分钟内过期缓存；超过 60 分钟或额度周期后拒绝展示为当前数据。Analytics 为每个官方响应保存可用性，未返回与真实零值分开呈现。本机 Codex 日志使用固定大小 POSIX 缓冲区逐行解析，单条记录上限为 1 MiB；扫描状态以版本化 Property List 保存在系统 Caches 目录，后续启动只读取追加内容，缓存不可用时安全回退为完整扫描。

## 提供方扩展边界

`AIUsageProvider` 与提供方无关的快照模型为未来 Claude、Gemini、ChatGPT 和 API 用量接入保留稳定边界。`CodexUsageProvider` 只负责把现有 Codex 仓库结果映射到通用模型；未实现的服务不会出现在界面中，既有 Codex 刷新链路保持不变。

2.1.2 为 Provider 描述增加额度窗口、余额、本地/远程历史和成本估算能力声明，以及本机文件、CLI、网页登录、OAuth、API Key 等认证方式声明。注册表新增 `LocalClaudeUsageProvider` 作为第一个非 Codex 实现：只有用户明确授权后才解析 `~/.claude/projects` 的结构化 usage 数值、消息 ID 与时间戳，并把结果标为“本机 Token 用量”，不声称是 Claude 套餐额度。

`LocalUsageEventMonitor` 使用 macOS FSEvents 监听 `.codex/sessions` 与 `.claude` 本机数据变化，1 秒合并抖动后调用 `refreshLocalUsage`。局部刷新只更新 Codex/Claude Token 模块，不访问网络额度数据源；系统睡眠时停止监听，唤醒后恢复。历史与当前快照可通过版本化 JSON/CSV 导出，脱敏诊断报告显式排除账号身份并再次经过 `SensitiveDataRedactor`。

菜单弹窗和完整面板统一通过 `UsagePresentationState` 表示加载、实时、缓存、估算、离线、需要登录、失败、不可用和已耗尽状态，视图不再分别推导数据源规则。
