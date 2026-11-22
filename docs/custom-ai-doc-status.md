# 自定义 AI 文档核对记录

日期：2026-11-18。

## 修改范围

- `validation.md`：区分已实现、本地验证、真实服务验证和发布前未完成项；记录默认 AI、自定义 AI、iOS 真实账号设置测试以及照片处理阻塞。
- `backend-runbook.md`：补齐已部署状态、安全配置、后续迁移/函数/Cron 更新顺序、完整照片链路验收、主密钥保留与数据保护回滚步骤。
- `setup.md`：同步安全配置检查、真实部署/测试证据及 Image Transform 阻塞。
- `scripts/check_config.py`：增强配置解析、权限/常规文件、公网地址格式与客户端敏感配置检查。`check_config_test.py` 由后端任务维护，本任务未修改。

配置检查器与 setup 文档曾存在并行所有权交叉；最后增量已向主任务交接，随后冻结这两个文件及检查器测试文件。本记录只说明交付证据，不改变部署授权或运行行为。

## 已核对证据

- `python3 scripts/check_config.py --simulator`：全部静态检查通过，只打印项目状态，不输出配置值、不发送网络请求。
- `python3 scripts/check_config_test.py`：6 项合成配置测试通过。初次执行的旧标签断言失败已修复并由最终结果覆盖。
- 核对现有日志：Flutter 51 项测试通过，analyze 无问题；Edge 76 项测试通过；数据库 AI settings 测试通过；iOS 真实账号 AI 设置 integration 通过。本次文档核对没有重新运行 Flutter、Edge 或数据库全套测试。
- 主任务确认新加坡 Supabase 13 份迁移、三个函数及 Vault Cron 已部署，默认 AI 合成图片探测和自定义配置 get/test/save/留空 key 重测/disable/delete 真实请求已通过。

## 未完成边界

实际照片处理仍收到 Storage Image Transform 的 `403 FeatureNotEnabled`，尚无开通确认。配置文件通过静态检查、AI 合成探测成功、Cron HTTP 200 和密码登录成功，均不代表完整照片打卡闭环或正式发布通过。

Apple/SMTP 登录全流程、APNs/极光送达、真实多账号全链路、真实设备、TestFlight 与正式签名 APK 仍需逐项验收。DNS 公网预检与实际连接之间仍有重绑定竞态，文档保留该部署层边界。

## 安全与操作范围

本次文档核对没有输出或复制真实密钥、JWT、账号密码，没有云端操作，没有重置主密钥、删除账号、清空任务或媒体。仅读取测试结果与公开配置说明；`.local/` 和签名文件继续由忽略规则保护。工作区当前未初始化 Git 仓库，因此没有执行 commit、push 或以 Git 回退文件。
