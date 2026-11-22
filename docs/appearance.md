# 可切换界面外观

在「设置 → 界面外观」选择「经典纸面」或「团团陪你」。首次安装默认经典纸面；选择后即时更新，本机重启后恢复。浅色与深色继续跟随系统。

团团外观包含今日、打卡、完成纪要、小队、计划和周报的插画与排版，以及通用按钮、表单、卡片和导航颜色。邀请、历史和 AI 设置继续使用原有操作流程并继承主题。人物头像仍来自真实用户资料，团团仅作为陪伴插画。

## 实现边界

- `app/lib/ui/app_appearance.dart` 管理本机偏好，键为 `better_together.appearance.v1`，不写入云端资料。
- `main.dart` 在启动前读取偏好；`app.dart` 保留同一个 GoRouter，仅重新构建主题，不重置账号、页面栈或业务状态。
- `ui/design.dart` 保留经典主题并提供团团主题；`ui/tuantuan.dart` 提供主题扩展和装饰插画。
- 偏好读取失败时显示可恢复状态，不覆盖原值；保存失败时保持当前外观并在选择页提示重试。
- 成功庆祝仅对已完成的盖章记录显示；AI 整理中、待重打、补卡等仍遵循真实记录状态。
- 周报导出继承当前主题，并继续只允许导出本人的个人周报。离屏长图不依赖异步插画解码。

素材全部随 App 打包，没有新增运行时依赖或远程字体请求。来源和许可证见 `app/assets/README.md`。

## 验证入口

使用 `bash scripts/flutter.sh` 执行 Flutter 命令。

- `test/appearance_preferences_test.dart`：默认值、重启恢复、双向切换、读写失败、竞态和重复保存。
- `test/appearance_ui_test.dart`：375、768、1024、1440 宽度，深浅色、1.6 倍字号、核心页面滚动，以及切换时账号、路由和业务快照保持。
- `test/report_export_test.dart`：两种外观的真实完成率、完整长图、主题继承与个人隐私校验。
- `integration_test/appearance_flow_test.dart`：iOS/Android 原生设置入口、双向切换、返回栈、本机持久化和重启恢复；截图由 `test_driver/integration_test.dart` 保存到 `output/qa/`。

集成测试仅注入 DemoRepository，不调用生产账号、AI、Storage 或业务接口，并在结束时恢复所用的演示数据和外观偏好。集成测试入口的构建包不能当作正常 App 分发；测试后须以 `lib/main.dart` 和本机安全配置重新构建。

## 回退

用户随时在同一设置页选择「经典纸面」，不需要退出账号或清除数据。代码回退不得卸载 App、清空 SharedPreferences 或修改云端资料。
