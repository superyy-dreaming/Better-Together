# 自定义 AI 后端状态

已完成 API 的 get_ai_settings / save_ai_settings / delete_ai_settings / test_ai_settings 四个动作、domain 白名单、013 迁移和 ai_settings.ts。所有动作都先鉴权，只使用认证得到的 user.id；请求体 user_id 无效。仅返回启用、地址、协议、模型和 has_key 元数据。测试连接使用 worker 的 testAiProvider，不写配置、不发用户照片。

密钥采用 AES-256-GCM，随机 96-bit IV，AAD 绑定 userId。独立 ai_settings 表启用 RLS 且撤销 public/anon/authenticated 所有表权限，仅 service_role 可操作；账号删除 cascade，删除中账号触发器禁止配置新增/修改。空密钥仅在同一规范化地址沿用；改地址必须提供新密钥。停用已有同址配置和清除不依赖 DNS 或加密主密钥可用性，停用保留密文，重新启用/实际使用重新校验。

端点校验 HTTPS、无用户信息/query/fragment、本机/内网/metadata、IPv4 非常规表示、IPv6 映射/保留/文档网段；A 和 AAAA 每条结果均必须是公网。已修复 IPv6 扩展写法绕过、空 query/fragment 被 URL 隐藏、数组协议被 String() 接受的问题。每次使用前校验，adapter 使用 redirect:error。供应商和数据库原始错误不进入返回值。

生命周期：DNS 暂不可用、配置存储不可用、服务器主密钥配置不可用均标 retryable，沿用既有 AI 当日重试窗口/次数和报告 72h 窗口，不把依赖故障直接判为永久失败。密文认证失败仍要求用户重新填写 key，绝不默认回退。

验证：
- ai_settings_test.ts：11/11 通过（加密隔离、篡改/错误主密钥、密钥沿用、地址格式、全部 DNS 结果、元数据脱敏、临时依赖错误仍可恢复）。
- ai_settings_api_test.ts：7/7 通过（真实 handler + Supabase/供应商 fetch 模拟，包含鉴权、本人作用域、保存加密、读取脱敏、幂等删除、故障可停用、合成图片严格 JSON 测试不保存、供应商错误脱敏、启用错误禁止默认回退）。
- 全新 PostgreSQL 17 临时集群：原 4 组 + ai_settings.sql 第 5 组全部通过，日志 output/qa/custom-ai-database-test.log。
- 三个 Edge 入口 deno check 通过。
- 所改后端文件 Deno lint 通过。
- 当前全量 Edge 测试 76 passed / 0 failed（`--allow-env --allow-read`）：worker 已修正旧 ai_test.ts 的 DNS fixture，生产 DNS 校验保持启用。日志 output/qa/custom-ai-edge-test.log。

配置检查已增加 `--simulator`（保留默认发布完整检查），校验 HTTPS AI 地址、两种协议及严格 base64/32 字节加密主密钥。`python3 -m unittest discover -s scripts -p check_config_test.py -v` 的 6 组临时虚构文件测试通过，覆盖默认与模拟器范围、完整配置、协议默认值、错误 URL/key 拒绝、凭据不输出与权限限制。测试不读取真实 `.local/`；`.env.example` 补加密主密钥说明，setup.md 补自定义 AI 操作与 root 确认的部署/Storage 阻塞现状，未修改历史 validation.md。

待 root/worker 确认的部署边界：Deno 官方 fetch/CreateHttpClientOptions 未提供 DNS 查询结果固定到连接的接口。当前应用层在 fetch 前查全 A/AAAA 并拒绝内网，加上 redirect:error；但仍有 DNS 查询与 fetch 自身解析间的 TOCTOU 窗口。要宣称完全防止恶意 DNS 重绑定，需要部署层出站网络阻断内网/metadata，或增加具备公网解析与固定连接能力的受控 egress proxy。不能将当前校验描述为已证明消除此竞态。已查阅 Deno Fetch API、OWASP SSRF Prevention Cheat Sheet、MDN AesGcmParams（2026-11-18，网页工具无结果时用 curl 读取官方文档）。

未读取/输出真实凭据，未执行远端迁移/部署。回滚函数可回退到此前版本，013 数据保留，迁移只追加修复，不删除存储密文或重置数据。
