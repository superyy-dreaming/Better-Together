# 自定义 AI 客户端交付

## 已实现

- `app/lib/features/settings/ai_settings_page.dart` 提供 `AiSettingsPage`，root 已接入 `/settings/ai`。
- 直接通过已鉴权的 repository.action 调用 `get_ai_settings`、`save_ai_settings`、`test_ai_settings`、`delete_ai_settings`，不把密钥加入 AppSnapshot。
- 默认/自定义服务状态、照片与纪要发送说明、两种协议、HTTPS 地址、模型、密码样式密钥、测试、保存、停用、确认清除均已实现。
- 已有密钥不回显；地址未变可空 key 沿用；地址改变立即提示并要求新 key。测试按当前输入发起，明确只用合成图片且不保存配置。
- 操作防重、加载/读取重试、内联错误、保留失败输入。成功保存和离页释放密钥；直接切换账号清空表单并忽略旧请求响应。错误文案对当前输入密钥额外遮盖。
- 外置标签已改为常驻 InputDecoration.labelText，VoiceOver 可关联字段。单个完整 Form Column 保持所有字段挂载，屏外字段仍参与校验。
- Demo Repository 的读取返回未配置状态，保存/测试/删除均明确拒绝真实服务操作，不把密钥持久化。演示页面禁止密钥输入并提示连接真实账号。
- `app/lib/domain/ai_settings.dart` 只存安全元数据，并提供地址格式校验/尾缀规范化；服务端仍负责公网、DNS、重定向校验。

## 验证与主线程下一步

- 已运行针对性 Dart analyze：无问题。
- `app/test/ai_settings_test.dart` 已完成 11 个用例（含循环产生的深浅色 375px 1.6x 字体场景），覆盖字段、空 key、地址变更、测试不保存/防重、失败保留、停用/确认清除、读取重试、演示拒绝、账号切换、Demo 不持久化密钥。
- 初次测试发现 ListView 卸载屏外字段，已修复为完整表单挂载。随后定位到测试 helper 在 ensureVisible 后尚未 pump，点击使用了滚动前坐标；已等布局稳定再点击，并设置 `hitTestWarningShouldBeFatal=true`，未隐藏警告。
- 主线程授权独占运行后，`flutter test test/ai_settings_test.dart --no-pub` 11 项全部通过。Flutter 进程已结束，主线程可继续全量测试、平台构建和真实截图。
- 建议命令：`bash scripts/flutter.sh test test/ai_settings_test.dart --no-pub`。
- 真实服务联调需要后端四个 action 已部署；客户端没有用成功占位替代服务结果。

## 设计依据与回滚

沿用 OJO/现有 DESIGN.md 与系统控件，采用 Impeccable harden/craft-floor 的失败恢复和大字体约束，无新增依赖。回滚时移除 root 的路由/入口和新页面、元数据文件及 Demo 的四个 action；不改已保存服务器数据。
