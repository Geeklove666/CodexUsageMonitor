# Codex Usage Monitor

<p align="center">
  <img src="CodexUsageMonitor/Resources/AppIcon.png" width="128" height="128" alt="Codex Usage Monitor 图标">
</p>

<p align="center">
  原生 macOS 菜单栏 Codex 用量监控器
</p>

> [!IMPORTANT]
> 本项目是独立开发的非官方工具，与 OpenAI 无隶属、授权或背书关系。Codex、ChatGPT 及 OpenAI 是其各自权利人的商标。

当前本地版本：**2.0.3（Build 35）**<br>
系统要求：**macOS 15 Sequoia 至 macOS 27 测试版**<br>
架构：**Apple Silicon（arm64）**

## 项目目标

Codex Usage Monitor 将额度、重置时间、Token 趋势和数据来源状态集中在菜单栏与独立 Dashboard 中。项目遵循三个原则：

1. 未知值保持未知，不用 `0` 伪装缺失数据；
2. 官方数据、缓存和估算值始终标明来源与可信度；
3. 登录、历史和诊断信息留在本机，不经过开发者服务器。

## 功能

### 菜单栏和面板

- 菜单栏显示主额度剩余比例与重置倒计时；无可靠数据时显示 `--%`；
- 按剩余额度显示绿、蓝、黄、橙、红五档状态；
- 360 pt 紧凑面板显示主/次额度、Token 摘要、来源和刷新状态；
- 固定布局的按钮按压反馈，不改变弹出面板尺寸；
- 一键刷新、打开完整面板、OpenAI 登录、本机 Token 授权、设置与退出。
- 可选启用“本机 Codex 登录”，直接使用这台 Mac 已登录 Codex 的额度数据。

### 用量和分析

- 主额度、次级额度、Credits、重置时间与可用重置次数；
- 近 30 天每日 Token、累计 Token、单日峰值与连续活跃天数；
- 在官方页面实际返回时展示线程、轮次、Skills、Plugins、模型和产品入口；
- 本机实时今日 Token 与官方历史日汇总按自然日合并；
- SwiftData 快照历史及 5 小时、24 小时、7 天趋势图；
- 每消耗 20% 的可选通知和高可信度额度重置检测。

### 稳定性和隐私

- 额度与 Analytics 独立获取，较慢的分析不会阻塞额度显示；
- 启用后优先使用本机 Codex 登录读取额度；不可用时回退到应用内隔离的 OpenAI 官方页面会话，单次请求最长 20 秒；
- 缓存按 5/15/60 分钟区分新鲜、可用和过期状态；
- Authorization、Cookie、Token、Session ID、Email 和敏感查询参数脱敏；
- 页面结构变化时失败关闭，不猜测字段含义；
- 离线测试不访问 OpenAI 或 GitHub。

## 数据来源

| 优先级 | 来源 | 主要字段 | 说明 |
|---:|---|---|---|
| 1 | 已验证官方方式 | 当前尚无稳定 CLI 额度命令 | 保留协议入口，不调用推测接口 |
| 2 | 本机 Codex 登录 | Codex app-server 返回的额度、Credits、重置窗口 | 需要用户授权，只调用 OpenAI 签名的本机 codex 命令 |
| 3 | 应用内 OpenAI 官方页面 | 页面可见额度及实际返回的分析模块 | 使用独立 WKWebView 登录态，不复用浏览器 Cookie |
| 4 | SwiftData 缓存 | 先前读取成功的真实快照 | 超过额度周期或 60 分钟后不作为当前数据 |
| 5 | 本地估算 | 主额度短期趋势 | 至少需要两个真实快照并显示 `≈` |

额度与 Analytics 可能来自不同来源。合并时按模块保留来源，缺失模块不会被虚构。完整调查见 [数据源调查](Docs/DataSourceInvestigation.md)。

## 本机读取范围

启用“本机实时今日 Token”后，仅扫描 `~/.codex/sessions` 中结构化 `token_count` 事件的时间戳和累计数值。应用忽略提示词、回复、代码、工具输出、文件路径和消息正文。本机值不包含其他设备或尚未落盘的活动。

更多信息见 [隐私说明](Docs/Privacy.md)。

## 安装

### 从 DMG 安装

1. 从项目 Release 下载最新 DMG；
2. 打开 DMG，将 **Codex Usage Monitor** 拖入 **Applications**；
3. 正式包完成 Developer ID 签名与 Apple 公证，可从“应用程序”正常打开。

不要关闭 Gatekeeper，也不要使用命令全局禁用 macOS 安全检查。当前仓库不附带 Developer ID 证书，维护者本地生成的 ad-hoc 包仅适合测试。

### 从源码运行

```bash
git clone https://github.com/Geeklove666/CodexUsageMonitor.git
cd CodexUsageMonitor
swift build
swift test
swift run CodexUsageMonitor
```

也可以直接用 Xcode 打开 `Package.swift`，选择 `CodexUsageMonitor` scheme。macOS 27 beta 环境需使用匹配的 Xcode 27 beta：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

## 首次使用

1. 启动应用并点击菜单栏中的 `Codex` 状态项；
2. 如需使用本机 Codex 额度，选择“启用本机 Codex”，并确保 `codex login status` 显示已登录；
3. 也可以选择“OpenAI 登录”，在隔离的官方页面中完成回退数据源登录；
4. 返回菜单栏点击“刷新”；若会话未就绪，应用会再次打开登录窗口；
5. 在设置中按需开启通知、登录启动、实时今日 Token 和历史保留周期；
6. 完整 Dashboard 使用 Overview、Usage History、Alerts、Data Source、Settings 五个页面；当前第一版界面使用明确标记的 Demo 数据展示各类状态。

官方 Usage 页面：<https://chatgpt.com/codex/settings/usage>

## 数据准确性

- `verified/high`：来自明确、已验证的当前数据源；
- `medium`：来自较旧但仍有效的真实快照；
- `cached`：先前真实快照，界面显示新鲜度；
- `estimated`：根据历史快照计算，始终带 `≈`；
- `unavailable`：无法可靠读取，界面显示“暂无数据”而不是零。

官方账户日汇总可能延迟。本机实时值只覆盖当前 Mac，因此不能与跨设备账单或组织统计直接等同。

## 刷新和存储

- 检测到 Codex 进程时默认约 60 秒刷新，否则约 5 分钟；
- 额度查询和本机实时 Token 扫描并发执行，Analytics 在额度显示后于后台补充；
- 未登录时刷新会展示登录窗口；已登录时额度请求直接使用 `no-store` 读取最新值；
- 倒计时只在本地更新，不触发网络请求；
- 相同数据通常不重复写入；数值变化达到 0.5%、重置时间变化、来源变化或间隔达到 10 分钟时保存快照；
- 历史默认保留 30 天，可选 7/30/90 天；
- 可在设置中分别清除历史、网页登录态或全部本地数据。

## 架构

```text
App / DependencyContainer
├── Features
│   ├── MenuBar
│   ├── Dashboard
│   ├── Login
│   └── Settings
├── Services
│   ├── UsageMonitoringService
│   ├── NotificationService
│   └── System / LaunchAtLogin
├── Data
│   ├── Sources
│   ├── Parsing
│   ├── Repository
│   ├── Persistence
│   └── Security
└── Domain
    ├── Models
    └── Protocols
```

技术栈为 SwiftUI、Swift Concurrency、SwiftData、Swift Charts、WebKit、UserNotifications 和 ServiceManagement。Features 只消费统一快照，不直接联网或解析页面。详见 [架构文档](Docs/Architecture.md)。

## 测试

```bash
swift test
```

当前包含 **59 项 XCTest**，覆盖：

- 百分比、重置时间和格式化边界；
- 官方页面、Usage 响应与 Analytics 解析；
- 本机 Codex app-server 额度解析；
- 本机实时 Token 只读取 `token_count` 事件；
- 数据源优先级、超时、缓存和估算降级；
- SwiftData 持久化和恢复；
- 脱敏规则与官方域名白名单；
- 菜单面板、Dashboard 关键宽度及稳定按压布局。

Fixture 必须最小化并脱敏，维护要求见 [Parser 维护](Docs/ParserMaintenance.md)。

## 打包

正式发布需要 Developer ID Application 证书和 Apple 公证：

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="notary-profile" \
Scripts/package-dmg.sh
```

仅本机开发验证可使用：

```bash
ALLOW_ADHOC=1 Scripts/package-dmg.sh
```

脚本生成仅含 arm64 的 Apple Silicon DMG、SHA-256 校验文件，并强制验证最低 macOS 15。ad-hoc 产物会明确命名为 `local-test`，只能在本机开发验证；对外分发必须使用 Developer ID Application、Hardened Runtime 和 Apple 公证。

## 常见问题

### 一直显示 `--%`

打开“OpenAI 登录”确认官方页面已登录，再返回菜单栏刷新。若诊断提示页面结构变化，需更新脱敏 Fixture 和解析规则。

### 今日 Token 与官方页面不同

本机实时值只统计当前 Mac 已落盘事件；官方值可能跨设备且存在日汇总延迟。

### 点击按钮时整个菜单面板缩放

1.8.3 已统一移除菜单栏、Dashboard 和设置页按钮的尺寸缩放，并取消整块内容的弹簧/位移动画。按钮现在只改变自身颜色和透明度，窗口与弹出面板布局保持不变。

### 无法生成可分享 DMG

没有 Developer ID 或公证配置时脚本会主动拒绝正式分发包。`ALLOW_ADHOC=1` 仅用于本机测试。

## 项目文档

- [版本记录](CHANGELOG.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)
- [架构](Docs/Architecture.md)
- [隐私](Docs/Privacy.md)
- [数据源调查](Docs/DataSourceInvestigation.md)
- [Parser 维护](Docs/ParserMaintenance.md)
- [构建报告](Docs/BuildReport.md)
- [DMG 安装说明](Docs/DMG安装说明.txt)

## 许可证状态

源代码目前公开供查看、审计和协作，但仓库尚未授予开源许可证。除法律明确允许的情形外，复制、修改或再分发前请先取得版权所有者许可。后续如采用 MIT、Apache-2.0 等许可证，将在独立 `LICENSE` 文件中明确说明。

## 免责声明

本软件按现状提供，不保证 OpenAI 官方网页结构长期不变。请勿将界面数据作为账单、财务或合同依据；最终信息以 OpenAI 官方页面和账户记录为准。
