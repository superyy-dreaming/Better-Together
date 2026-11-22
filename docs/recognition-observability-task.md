# recognize failure observability

ai_worker 请修 supabase/functions/recognize/index.ts：目前 catch 返回 generic pending 却没有结构化日志，真实某些合成图片连续pending但模拟器另一张已ready，无法区分schema/provider/config/timeout根因。增加 console.error/info event=recognition_pending 与受控ServiceError.code（未知只UNEXPECTED，不message/stack/body）。可含photo_id，绝不请求图片、密钥或provider URL。补针对性mock测试证明pending不会输出敏感消息，Deno tests/check通过。不要改timeout参数、不改客户端或其他业务。生产使用当前默认硅基流动model，root诊断实际错误。写docs/recognition-observability-status.md供root部署。
