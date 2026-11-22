# 接入真实内测环境

应用已提供显式本机演示模式。正式模式默认关闭演示，缺少配置时显示连接说明，不生成示例数据。

## 安全文件

`.local/` 已被 Git 忽略，目录权限 700、文件权限 600。不要把 secret 粘贴到聊天、源码或截图里。

- `.local/client.json`：Supabase URL、anon/publishable key，DEMO_MODE 保持 false。客户端只允许公开配置，不填 service_role 或 OpenAI key。
- `.local/server.env`：只包含任务、APNs、极光等非 AI 服务端参数。禁止写入 AI 密钥、默认 AI 模型或加密主密钥。Supabase 自动提供自己的服务端凭据，无需复制进客户端。
- `.local/ios-signing.xcconfig`：Apple Team ID、已注册 Bundle ID；配置好后复制到 `app/ios/Flutter/Signing.local.xcconfig`。
- `.local/android-key.properties`：已有 keystore 绝对路径、别名、口令、包名；配置好后复制到 `app/android/key.properties`。不要覆盖已有正式证书。
- `.local/android-push.properties`：极光 App Key；配置好后复制到 `app/android/push.properties`。

Supabase 项目位于新加坡。打卡图片由客户端压缩，由 App 直连本人配置的 Chat Completions 服务识别，用户确认后将原图存入私有 Storage，不依赖 Storage Image Transform。邮箱 SMTP 模板应显示 `{{ .Token }}`；OAuth Auth 回调白名单应包含 `bettertogether://auth/callback`，这些配置需单独验收。iOS Apple 登录需要同时开启 App ID 对应能力、Supabase Apple provider，并在 Client IDs 中登记相同 Bundle ID；原生登录已通过真机验证，详见 [登录验收](auth-acceptance.md)。Android Apple 网页登录另需 Services ID/client secret。APNs/极光真机测试需要匹配包标识。

填好后在项目根目录运行 `python3 scripts/check_config.py --simulator`，检查模拟器连接与非 AI 后端配置；默认不带参数的 `python3 scripts/check_config.py` 另检查发布签名和真机推送。脚本只打印各项是否就绪，不输出配置值、不连接云服务；会检查目录 700、配置常规文件 600、重复配置项、HTTPS/已知非公网地址、密钥格式和客户端私密字段。它不查询 DNS，也不验证供应商密钥有效性。脚本自身测试为 `python3 scripts/check_config_test.py`，只使用临时合成配置。

## 自定义 AI

登录后打开「设置 → AI 识别」，填写 HTTPS 接口地址、模型名与 API Key。仅 Chat Completions，图片以 base64 image_url 发送；支持严格 JSON Schema 或经连接测试确认的 JSON Object，均在本机严格校验。测试只发合成图片，不保存配置。

密钥只存本设备当前账号的 iOS Keychain / Android Keystore 保护存储，不回显、不上传后端。地址改变必须重新填写 Key，停用保留本机配置，清除后保持空白。没有默认服务，未配置或失败时仍可盖章，在详情补生成；App 挂起后恢复任务，自动重试限当天，过期由用户主动触发。周报规则统计始终可见，AI 只在本人打开周报时选择已核实的事实，按周报版本复用。部署步骤见 [BYOK 切换与回滚](byok-rollout.md)。

## 运行

```sh
# 本机演示，不上传任何照片
bash scripts/flutter.sh run --dart-define=DEMO_MODE=true
# 已配置的真实服务
bash scripts/flutter.sh run --dart-define-from-file=../.local/client.json
# 测试
bash scripts/flutter.sh analyze
bash scripts/flutter.sh test
PATH=/opt/homebrew/opt/postgresql@17/bin:$PATH bash supabase/tests/run.sh
npx --yes deno test --allow-env --allow-read supabase/functions/_shared/
```

`scripts/flutter.sh` 在 app/ 目录执行，因此 define 文件使用 `../.local/`。完整 Xcode 安装路径和 Flutter SDK 可在脚本中查看；不需要改系统 Xcode 选择。

## 部署与分发顺序

截至 2026-11-18，当前新加坡 Supabase 内测项目已执行 13 份迁移，部署 `api`、`media`、`worker` 三个函数并设置 Vault Cron，CLI 已登录。最近观察到 3 次 Cron worker HTTP 200 且无超时。默认 AI 的 `https://api.siliconflow.cn/v1`、`deepseek-ai/DeepSeek-V4.1-Flash`、Chat Completions 组合已通过本地和云端合成图片 strict JSON 探测；认证账号的 get/test/save/留空 key 重测/disable/delete 已实测通过。iOS Simulator 已用真实 Supabase 测试账号完成设置入口与 AI 页面 integration，账号保留供后续使用。这些证据不代表真实照片分类准确率、SMTP/Apple 登录或完整打卡闭环已通过。

旧照片链路曾被 Storage Image Transform 的 `403 FeatureNotEnabled` 阻塞。用户于 2026-11-18 明确改为「选图 → 长边不超过 1600 的压缩 JPEG → Edge 识别 → 确认/改标签 → 原图私有归档并盖章」，不再以开通 Transform 为前置条件。这是新的实施链路，前述旧函数部署、AI 探测与页面测试不能证明它已部署或验收。应先应用迁移 014、部署含 `recognize` 的四个入口与更新客户端，再验证识别阶段无 Storage 写入、确认后盖章、故障 ALL 与当天后台补识别。

后续更新按 [backend-runbook.md](backend-runbook.md) 核对迁移、函数和 Vault Cron，使用合成照片完成两账号测试，再验证 Apple、SMTP、日期/去重/私有归档、AI、通知点击和删除账号。发布签名和真机推送不阻塞模拟器接入。

真实用户启用前补齐运营主体、完整隐私政策及联系方式、跨境数据说明，确认本地区实际连通性。当前应用内隐私页明确说明这些待补事项。

iOS：`bash scripts/flutter.sh build ipa --dart-define-from-file=../.local/client.json`，使用明确选择的开发团队与 provisioning profile；在 App Store Connect 上传并等待处理后才能邀请 TestFlight 用户。Android：`bash scripts/flutter.sh build apk --release --dart-define-from-file=../.local/client.json`，签名配置缺失会失败。debug APK 仅用于开发验证，不能当正式内测分发包。

发布前进行真实设备烟测。没有实际上传/签名/送达证据时，不把构建成功表述为已分发。
