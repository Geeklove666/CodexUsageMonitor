# 构建与测试记录

日期：2026-07-17

## 工具链

- macOS 27.0 beta 3 v2（26A5378n）
- Xcode 27 beta 3（27A5218g）
- macOS 27 SDK
- Swift 6.4
- 项目使用 Swift Package；命令显式设置 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`

## App 构建

执行：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift package clean
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build
```

最终结果：成功，0 个错误。当前版本为 1.8.8（Build 31），最低部署版本 macOS 14。Xcode 27 beta 在构建 Universal 2 时提示 `x86_64` 对 macOS 27 部署目标已弃用；最终二进制仍同时包含 `arm64` 与 `x86_64`，其 `LC_BUILD_VERSION` 最低版本为 14.0。

## XCTest

执行：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

最终结果：68 个 XCTest 全部通过，0 个失败、0 个未执行。覆盖 WebView 注入脚本、今日 Token、app-server Credits/个人消费限制、临时错误重试策略、字段来源合并、额度短缓存、授权恢复路由、缓存刷新状态、Analytics 缓存恢复，以及设计系统不再应用缩放变换的回归。原先未被主程序依赖的重复 `Core` Package 已移除。

## 启动冒烟测试

执行 Debug 可执行文件后等待 5 秒。进程保持运行，无 stdout/stderr 错误，证明 SwiftUI 菜单栏应用完成启动且未立即崩溃。

## 1.8.8 本机测试 DMG

- 文件：`Codex-Usage-Monitor-1.8.8-local-test-universal.dmg`；
- 架构：`arm64`、`x86_64`；
- 最低 macOS：14.0；
- 签名：ad-hoc，仅供本机开发测试，不能作为跨 Mac 分享版；
- Apple 公证票据：无；
- SHA-256：`387066f42f4e1ba0a2f40cda177bb1b6e605bc610fa5ad3f0991338ec3e03071`。

## 本轮刻意保留

- 当前钥匙串没有 Developer ID 身份，因此不能生成可信分享版；脚本现在会拒绝静默生成未签名/未公证的发布包。`ALLOW_ADHOC=1` 只用于本机开发验证，并强制在文件名中加入 `local-test`；
- GitHub Actions CI 已配置为在 push 和 pull request 时验证元数据、构建并运行测试；
- 真实账户页面仍可能随 OpenAI 更新，需要持续使用脱敏 Fixture 回归验证。
