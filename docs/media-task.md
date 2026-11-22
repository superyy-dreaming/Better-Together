# 追加实施任务

完成：source=avatar 已实现，33个Deno测试通过。最终状态、接口、真实Storage精确待验项见 docs/worker-status.md。

请 ai_worker 负责实现 source=avatar 图片上传：私有 avatars bucket，验证图片/大小，绕过打卡日期/去重，返回 `{id,path,source:'avatar',captured_at}`，后续客户端 action save_profile `{avatar_url:path}`。backend api 已可签名头像 URL 并校验 `${user.id}/` 前缀。不能让客户端直接提交外部URL或其他用户头像。

请提供测试与 docs/worker-status.md。既有 functions/.env.example、ai.md 已被主线程读取。完成头像后请审查现有 media 真实Storage转换链路可能失败的格式/路径问题，写出精确未验证项。

此文件用于跨agent可读任务传递，完成后可删除。
