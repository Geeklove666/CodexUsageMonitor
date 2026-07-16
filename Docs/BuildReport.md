# 构建与测试记录

日期：2026-07-16

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

最终结果：成功，0 个错误。当前版本为 1.8.2（Build 25），最低部署版本 macOS 14。Xcode 27 beta 在构建 Universal 2 时提示 `x86_64` 对 macOS 27 部署目标已弃用；最终二进制仍同时包含 `arm64` 与 `x86_64`，其 `LC_BUILD_VERSION` 最低版本为 14.0。

## XCTest

执行：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

最终结果：63 个 XCTest 全部通过，0 个失败、0 个未执行。覆盖 WebView 注入脚本、今日 Token、app-server Credits/个人消费限制、字段来源合并、Analytics 缓存恢复，以及菜单面板按钮按压不改变布局缩放的 1.8.2 回归。原先未被主程序依赖的重复 `Core` Package 已移除。

## 启动冒烟测试

执行 Debug 可执行文件后等待 5 秒。进程保持运行，无 stdout/stderr 错误，证明 SwiftUI 菜单栏应用完成启动且未立即崩溃。

## 1.8.2 DMG

- 文件：`Codex-Usage-Monitor-1.8.2-universal.dmg`；
- 架构：`arm64`、`x86_64`；
- 最低 macOS：14.0；
- 签名：ad-hoc，仅供开发测试；
- SHA-256：`a24c003422fd1b4084fbb2ee7f3e9d59d38e4feebc426979807ac39ccfd593cd`。

## 本轮刻意保留

- 当前钥匙串没有 Developer ID 身份，因此不能生成可信分享版；脚本现在会拒绝静默生成未签名/未公证的发布包。`ALLOW_ADHOC=1` 只用于本机开发验证；
- GitHub Actions CI 已配置为在 push 和 pull request 时验证元数据、构建并运行测试；
- 真实账户页面仍可能随 OpenAI 更新，需要持续使用脱敏 Fixture 回归验证。
