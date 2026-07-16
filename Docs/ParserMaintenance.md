# Parser 维护

当前 parserVersion 为 `2026.07-conservative-1`，只接受用户可见文本中无歧义的“百分比 + remaining/剩余”。缺少 Credits、次级窗口或重置时间会返回部分结果；找不到主额度会抛出 `pageStructureChanged`。

维护流程：在应用自有登录会话中人工确认页面 → 生成不含姓名、邮箱、账号、Cookie、Token 的最小 Fixture → 增加正常、缺字段、类型变化和结构变化测试 → 集中更新选择规则 → 提升 parserVersion → 运行全部离线测试。不得提交完整网页、响应头或账号数据，也不得把网页内部请求称为公开 API。
