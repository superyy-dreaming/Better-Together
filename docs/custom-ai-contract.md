> 历史记录：本文中的后端持钥、代理和服务器 AI 任务已由设备 BYOK 架构替代。不得据此恢复旧链路。当前实现见 [ai.md](ai.md) 和 [byok-rollout.md](byok-rollout.md)。

# 自定义 AI 当前实施契约

用户已要求在设置中添加自定义 API，实际识别必须使用配置。保持后台异步识别（不在设备直接调用供应商），每账号独立。沿用 OJO DESIGN.md、ui-ux-pro-max、Impeccable harden/craft-floor。

## API（backend 所有）

现有 api action 新增 get_ai_settings / save_ai_settings / delete_ai_settings / test_ai_settings。必须鉴权本人。

- get_ai_settings -> {enabled:bool,base_url:string,protocol:'responses'|'chat_completions',model:string,has_key:bool}，绝不返回密钥/密文。
- save_ai_settings args {enabled,base_url,protocol,model,api_key?:string}。空key或省略仅在地址未变时沿用已有key；地址改变必须提供新key，防旧密钥发送到新站。enabled=false可停用但保留配置。key加密存储，不放profiles/bootstrap/日志。
- delete_ai_settings -> {deleted:true}，恢复默认。
- test_ai_settings args同save，使用当前输入（空key规则同上）；小型合成图片+strict JSON探测可用性，不保存配置、不发送用户照片。返回 {ok:true,message:string}，失败用安全ServiceError。调用worker提供的testAiProvider(config)。

## shared 配置接口（backend 所有）

supabase/functions/_shared/ai_settings.ts 导出：
type AiProviderConfig={baseUrl:string,protocol:'responses'|'chat_completions',model:string,apiKey:string}
loadAiProvider(userId:string):Promise<AiProviderConfig|undefined>：undefined使用默认，已启用配置错误明确失败、不可静默默认。
validateAiEndpoint(baseUrl:string):Promise<string>：HTTPS、无userinfo/query/fragment、公共DNS和公网IP、拒绝内网/localhost/metadata/redirect。返回去尾/并规范的baseUrl（用户填 /v1，可容忍完整接口尾缀规范化）。

AES-GCM用户密钥密文存独立RLS表，浏览器/客户端无select权限，service_role访问，账户删除cascade。服务端AI_SETTINGS_ENCRYPTION_KEY为32字节base64，由root生成到.local/server.env且不输出。使用AAD绑定userId。所有custom请求redirect:error，每次使用前重新验证端点。供应商原始错误体不返给用户也不打日志。

## AI Adapter（ai_worker 所有）

修改 _shared/ai.ts：structuredResponse末尾新增可选provider，保持原调用与test兼容；Responses不向任意第三方强发reasoning参数；Chat Completions走/messages、image_url、response_format json_schema strict，解析choices.message.content/refusal。保持现有日期/归类/数字/Schema校验，不能仅信任JSON可解析。

generateMemo/recognizeScreenshot/周报AI调用都接受provider，worker按job.user_id加载、media按当前user.id加载。自定义失败不回退默认，不撤销盖章。导出testAiProvider(provider)，合成小图+JSON验证（无需用户照片）。依赖backend提供ai_settings.ts，如暂未存在可以等接口落地。

## Flutter（client_data 所有）

新 AiSettingsPage，settings页入口、路由由root接入（请告知类/文件）。api action读取保存测试删除；表单明确服务地址、协议、模型和密码样式key（不回显已有key）；测试连接/保存/停用/清除，防重复、内联失败、离页释放密钥controller。以root existing repository.action使用，不给AppSnapshot塞key。照片发送给指定服务的说明可见，默认服务和自定义状态明确。

Demo：允许本地演示页面但不保存真实key到SharedPreferences。演示时真实保存/测试需明确提示先连接真实账号，不能伪造成功或偷偷调用默认。页面提示“演示模式，配置不会保存”。无新增依赖。

至少测试字段/空key保留/地址修改提示/失败状态/大字号深浅；backend测试加密隔离与RLS，worker测试两协议与真实调用路由/no fallback。

## 所有权

- backend：SQL新迁移013、api/index.ts、domain.ts、ai_settings.ts及其测试。
- ai_worker：_shared/ai.ts及adapter测试、worker/media/report接入，docs/custom-ai-worker-status.md。
- client_data：新settings UI、demo action、独立test，docs/custom-ai-client-status.md。不改app.dart，root接路由。
- root：运行环境、安全配置、部署探测、app.dart路由、整合构建。

把交付结果写对应status文件；协作消息可能被网关隐藏，应直接读此文件。

## 当前环境补充

- 用户已填写 OPENAI_BASE_URL，默认供应商请求必须尊重该值（留空时官方端点），不能忽略。默认兼容地址仍执行 HTTPS/公网校验且禁止重定向。root 已读取 OpenAI 官方 structured-outputs 和 images-vision 文档，两协议结构无新增依赖。
- root 已生成 AI_SETTINGS_ENCRYPTION_KEY 到 .local/server.env，保留，不读取或输出凭据。
- 远端 Auth settings 可达，Apple 登录未启用，/functions/v1/api 返回 404；CLI 尚未登录，已向用户请求登录部署工具。
- root 接入 AiSettingsPage 路由 /settings/ai；请客户端使用该类名。
