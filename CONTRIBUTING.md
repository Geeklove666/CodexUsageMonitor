# 贡献指南

感谢参与 Codex Usage Monitor。提交代码前请先阅读隐私和 Parser 约束；本项目宁可显示未知，也不猜测官方字段。

## 开始开发

1. Fork 仓库并创建主题分支；
2. 使用 macOS 14+ 和 Swift 6 工具链；
3. 运行 `swift test` 确认基线；
4. 保持变更聚焦，并为行为修复增加测试；
5. 在 PR 中说明用户影响、验证方式和隐私影响。

## 代码原则

- 使用 Swift Concurrency，避免阻塞主线程；
- Features 不直接解析网页或访问网络；
- 未返回与真实零值必须分开表达；
- 新数据源必须提供可用性、来源名、可信度和诊断信息；
- 不记录 Cookie、Authorization、Token、邮箱或原始账户响应；
- UI 需兼容浅色/深色、增加对比度、减少动态效果和 VoiceOver 标签；
- MenuBarExtra 内容的交互状态不得改变面板 fitting size。

## Fixture 和账户数据

禁止提交完整 HTML、响应头、Cookie、Token、账号 ID、邮箱、提示词、回复、代码或会话正文。Parser Fixture 只保留证明字段映射所需的最小结构，并使用虚构值。

## 验证

```bash
swift test
swift build
plutil -lint CodexUsageMonitor/Resources/Info.plist
plutil -lint CodexUsageMonitor/Resources/PrivacyInfo.xcprivacy
bash -n Scripts/package-dmg.sh
```

涉及界面时，请说明测试过的窗口宽度、颜色模式和减少动态效果设置。涉及 Parser 时，覆盖正常、缺字段、类型变化和结构变化。

## 提交和 PR

提交信息使用简短祈使句。PR 应包含：问题背景、实现摘要、测试结果、截图或录屏（如适用）、兼容性和隐私影响。不要把无关格式化或重构混入修复。
