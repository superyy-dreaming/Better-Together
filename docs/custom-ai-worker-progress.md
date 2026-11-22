# 自定义 AI Worker 接入进度

接口约定：structuredResponse 保留第五个 fetcher 参数，第六个可选 AiProviderConfig；generateMemo、recognizeScreenshot 第二参、generateReport 第三参为 provider。provider 未传使用原有默认；自定义配置每次在 adapter 中 validateAiEndpoint、redirect:error，不回退默认。

testAiProvider(provider) 由 ai.ts 导出，返回 Promise<{ok:true,message:string}>；使用合成红色 32×32 PNG 和 strict schema，只测图片识别/结构化输出，不读取用户照片。backend 可直接导入。额外可选 fetcher 便于测试。

ai_settings.ts 由 backend 按主契约提供；我不会创建或修改该文件。

当前在实现两协议 adapter、所有响应的本地 Schema 校验和 safe ServiceError。worker 依据 checkin.user_id / report.user_id 加载本人配置，media 依据 authenticate 的 user.id 加载截图 OCR 配置。
