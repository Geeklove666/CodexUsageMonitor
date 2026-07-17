# 构建与测试记录

日期：2026-07-17

## 工具链

- macOS 27.0 beta 3 v2（26A5378n）
- Xcode 27 beta 3（27A5218g）
- macOS 27 SDK
- Swift 6.4
- 项目使用 Swift Package；命令显式设置 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`

## 2.0.15 发布构建

执行：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build
```

最终结果：成功，0 个错误。当前版本为 2.0.15（Build 47），最低部署版本 macOS 15.0。产品包只面向 Apple Silicon，正式打包脚本使用 `--arch arm64`，并验证最终二进制只包含 `arm64`。

## XCTest

执行：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

最终结果：64 个 XCTest 全部通过，0 个失败、0 个未执行。覆盖 WebView 注入脚本、今日 Token、官方页面额度来源、本机 Codex app-server 额度解析、字段来源合并、缓存刷新状态、Analytics 缓存恢复、自动刷新频率、真实刷新诊断、Credits 两位小数显示、本机 Codex 空 reset credits 兼容、菜单按钮不重复启动登录流程、菜单栏标题使用系统默认颜色、DESIGN.md Dashboard 结构，以及设计系统不再应用缩放变换的回归。

## 数据源调整

2.0.1 重新加入用户授权的“本机 Codex 登录”额度读取链路。实现会先用 stable 的 `codex login status` 检查本机登录，再调用 OpenAI 签名的本机 `codex app-server --stdio` 读取额度；由于 app-server 官方成熟度仍为 Experimental，它只作为可选优先源，失败时继续回退到 App 内隔离的 OpenAI 官方 WebKit 会话、缓存与估算。本机 Token 统计仍为单独授权的本地读取能力。2.0.14 兼容 `rateLimitResetCredits.credits: null` 的真实返回结构，并把本机 Codex 额度读取超时单独放宽至 45 秒。

## UI 调整

界面按 Apple's Liquid Glass Design 重新整理：macOS 26 及以上使用原生 Liquid Glass 效果，macOS 15 使用系统 Material 降级方案。按钮按压态只改变透明度和填充，不再使用放大缩放，避免点击整块面板被放大的问题。2.0.2 进一步移除“更新今日 Token”独立按钮，改由“刷新”同步刷新额度和今日 Token；完整面板改为中文导航与中文 Demo 文案。2.0.3 移除“完整面板”按钮的大面积蓝色 tint，改为中性 Liquid Glass 控件。2.0.4 将菜单展开面板改为更接近 Apple popover 的大连续圆角、系统材质与柔和描边，并取消刷新时自动弹出网页登录窗口。2.0.9 移除菜单栏展开面板背后的自定义半透明 Material 遮罩。2.0.10 将 MenuBarExtra 宿主 NSWindow 配置为透明、非 opaque、无系统窗口阴影，并清理 NSHostingView / contentView 背景；菜单根 View 只绘制一个与实际内容尺寸一致的圆角主面板，圆角外透明。2.0.11 在完整面板和设置页加入 1/5/10 分钟自动刷新频率，并将刷新调度收敛为单一可见配置。2.0.12 新增智能刷新、菜单打开按需刷新和完整面板真实刷新诊断。2.0.13 将菜单栏弹窗宿主从 SwiftUI MenuBarExtra 切换为自建透明 NSPanel，避免系统宿主窗口在圆角外绘制额外背景。2.0.6 曾将设置页数据源区域改为电池充电绿；2.0.7 已取消该填充色，改为中性 Liquid Glass 操作按钮。

## 启动冒烟测试

本地安装到 `/Applications/Codex Usage Monitor.app` 后启动成功，进程保持运行，没有立即崩溃。该测试验证的是本机可启动，不等同于跨 Mac 可分发签名验证。

## 2.0.15 本机测试 DMG

- 文件：`Codex-Usage-Monitor-2.0.15-local-test-apple-silicon.dmg`；
- 架构：`arm64`；
- 最低 macOS：15.0；
- 签名：ad-hoc，仅供本机开发测试，不能作为跨 Mac 分享版；
- Apple 公证票据：无；
- SHA-256：`5b068c00f836fb1d36d70fb57af81230727a3a44d2ebba46c115fac3ac74f898`。

## 发布阻塞项

当前钥匙串没有有效的 Developer ID Application 证书，因此不能生成可稳定分享给其它 Mac 的 Gatekeeper 可信安装包。正式分享版还需要 Developer ID 签名和 Apple notarization；脚本会拒绝在缺少这些凭据时静默生成“看似正式”的未公证包。`ALLOW_ADHOC=1` 只用于本机开发验证，并强制在文件名中加入 `local-test`。

## GitHub 状态

2.0.15 经用户明确要求同步 GitHub，完成提交、推送和 GitHub Release。
