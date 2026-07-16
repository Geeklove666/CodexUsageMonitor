# Codex Usage Monitor

<p align="center">
  <img src="CodexUsageMonitor/Resources/AppIcon.png" width="128" height="128" alt="Codex Usage Monitor 图标">
</p>

<p align="center">
  原生 macOS 菜单栏 Codex 用量监控器
</p>

> [!IMPORTANT]
> 本项目是独立开发的非官方工具，与 OpenAI 无隶属、授权或背书关系。Codex、ChatGPT 及 OpenAI 是其各自权利人的商标。

当前版本：**1.8.7（Build 30）**<br>
系统要求：**macOS 14 Sonoma 或更高版本**<br>
架构：**Apple Silicon + Intel（Universal 2 发布包）**

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
- 一键刷新、打开完整面板、授权本机数据源、打开设置或退出应用。

### 用量和分析

- 主额度、次级额度、Credits、重置时间与可用重置次数；
- 近 30 天每日 Token、累计 Token、单日峰值与连续活跃天数；
- 在官方页面实际返回时展示线程、轮次、Skills、Plugins、模型和产品入口；
- 本机实时今日 Token 与官方历史日汇总按自然日合并；
- SwiftData 快照历史及 5 小时、24 小时、7 天趋势图；
- 每消耗 20% 的可选通知和高可信度额度重置检测。

### 稳定性和隐私

- 额度与 Analytics 独立获取，较慢的分析不会阻塞额度显示；
- 本机额度源允许最长 35 秒冷启动、其他来源 15 秒请求超时；成功后 45 秒内复用真实快照，连续失败按 1/2/5/10/30 分钟指数退避；
- 缓存按 5/15/60 分钟区分新鲜、可用和过期状态；
- Authorization、Cookie、Token、Session ID、Email 和敏感查询参数脱敏；
- 页面结构变化时失败关闭，不猜测字段含义；
- 离线测试不访问 OpenAI 或 GitHub。

## 数据来源

| 优先级 | 来源 | 主要字段 | 说明 |
|---:|---|---|---|
| 1 | 已验证官方方式 | 当前尚无稳定 CLI 额度命令 | 保留协议入口，不调用推测接口 |
| 2 | 本机 Codex app-server | 套餐、额度窗口、重置、Token 日汇总 | 实验性；必须由用户主动授权 |
| 3 | 应用内官方页面 | 页面可见额度及实际返回的分析模块 | 使用独立 WKWebView 登录态，不复用浏览器 Cookie |
| 4 | SwiftData 缓存 | 先前读取成功的真实快照 | 超过额度周期或 60 分钟后不作为当前数据 |
| 5 | 本地估算 | 主额度短期趋势 | 至少需要两个真实快照并显示 `≈` |

额度与 Analytics 可能来自不同来源。合并时按模块保留来源，缺失模块不会被虚构。完整调查见 [数据源调查](Docs/DataSourceInvestigation.md)。

## 本机读取范围

启用“复用本机 Codex 登录”后，应用通过 Codex 自身的 `app-server` 请求账户聚合数据；不会直接打开 `~/.codex/auth.json`，也不会接收或保存登录 Token。

启用“本机实时今日 Token”后，仅扫描 `~/.codex/sessions` 中结构化 `token_count` 事件的时间戳和累计数值。应用忽略提示词、回复、代码、工具输出、文件路径和消息正文。本机值不包含其他设备或尚未落盘的活动。

更多信息见 [隐私说明](Docs/Privacy.md)。

## 安装

### 从 DMG 安装

1. 从项目 Release 下载最新 DMG；
2. 打开 DMG，将 **Codex Usage Monitor** 拖入 **Applications**；
3. 在“应用程序”中右键应用并选择“打开”；
4. 未公证的开发测试包可能需要在“系统设置 → 隐私与安全性”中选择“仍要打开”。

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
2. 选择“复用本机 Codex”，阅读隐私说明后决定是否授权；
3. 若本机数据源不可用，可选择“浏览器查看 → 应用内登录”；
4. 在设置中按需开启通知、登录启动、实时今日 Token 和历史保留周期；
5. 完整 Dashboard 可查看趋势、账户摘要和数据源诊断。

官方 Usage 页面：<https://chatgpt.com/codex/settings/usage>

## 数据准确性

- `verified/high`：来自明确、已验证的当前数据源；
- `medium`：来自可能随页面或本机接口变化的来源；
- `cached`：先前真实快照，界面显示新鲜度；
- `estimated`：根据历史快照计算，始终带 `≈`；
- `unavailable`：无法可靠读取，界面显示“暂无数据”而不是零。

官方账户日汇总可能延迟。本机实时值只覆盖当前 Mac，因此不能与跨设备账单或组织统计直接等同。

## 刷新和存储

- 检测到 Codex 进程时默认约 60 秒刷新，否则约 5 分钟；
- 额度查询和本机实时 Token 扫描并发执行，Analytics 在额度显示后于后台补充；
- 最近一次本机真实额度会短暂复用 45 秒，防止连续点击反复触发上游约 5 秒的查询；
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

当前包含 **67 项 XCTest**，覆盖：

- 百分比、重置时间和格式化边界；
- 官方页面、Usage API、app-server 与 Analytics 解析；
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

脚本生成 Universal 2 DMG、SHA-256 校验文件，并验证签名、架构和最低系统版本。

## 常见问题

### 一直显示 `--%`

确认“复用本机 Codex 登录”已经授权；仍不可用时打开应用内登录窗口。若诊断提示页面结构变化，需更新脱敏 Fixture 和解析规则。

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

本软件按现状提供，不保证额度字段、网页结构或实验性本机接口长期稳定。请勿将界面数据作为账单、财务或合同依据；最终信息以 OpenAI 官方页面和账户记录为准。
