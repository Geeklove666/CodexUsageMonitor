# 架构

应用采用 SwiftUI + Swift Concurrency + SwiftData。Domain 分别定义额度与 Analytics 数据源协议；Data 对额度按“官方已验证 / 用户授权的本机 Codex / 官方页面 / 持久化缓存 / 本地估算”顺序降级，再独立补充官方页面 Analytics；Services 负责进程、网络、刷新、通知与重置检测；Features 只消费合并后的统一快照，不直接联网或解析页面。

`DefaultCodexUsageRepository` 串行选择数据源，本机额度源允许最长 45 秒冷启动、其他来源 15 秒超时；本机真实额度使用 45 秒进程内短缓存。app-server 客户端先完成 `account/read(refreshToken: true)`，再发送 `account/rateLimits/read`，避免凭据刷新竞态；临时服务与连接错误会在 0.7–1.3 秒抖动后重试一次。`UsageMonitoringService` 保证同一时间只有一个额度刷新任务，并发读取本机实时 Token，额度完成后再由独立任务补充 Analytics。活动/空闲间隔为 60/300 秒，连续失败按 1/2/5/10/30 分钟退避并加入 5% 抖动。倒计时使用本地时间刷新，不触发网络请求。

缓存从 SwiftData 最近真实快照恢复，并持续为估算器提供历史。缓存新鲜度：5 分钟内新鲜、15 分钟内可用缓存、60 分钟内过期缓存；超过 60 分钟或额度周期后拒绝展示为当前数据。Analytics 为每个官方响应保存可用性，未返回与真实零值分开呈现。
