# AI 失败恢复云端探测脚本交接

交付：`scripts/direct_ai_failure_smoke.py`。只完成代码和离线语法检查，**没有运行真实请求，没有读取真实配置值，没有部署，也没有生成通过结果**。

## 运行条件与命令

由 root 在专用合成测试账号环境执行：

```sh
python3 scripts/direct_ai_failure_smoke.py
```

依赖 Python 3.10+、Pillow；不安装额外网络库。默认恢复等待 600 秒、每 10 秒触发 AI worker 并读取 bootstrap，可用 `--deadline-seconds`（30–900）和 `--poll-seconds`（2–30）调整。单次网络请求最多 110 秒，最终结束可能晚于轮询期限一个在途请求。

仅运行时读取以下私有文件，目录要求 700，常规文件要求 600，拒绝符号链接：

- `.local/simulator.json`：`SUPABASE_URL`、`SUPABASE_ANON_KEY`、`TEST_EMAIL`、`TEST_PASSWORD`。
- `.local/server.env`：`OPENAI_BASE_URL`、`OPENAI_PROTOCOL`、`OPENAI_API_KEY`、`JOB_SECRET`。
- `.local/cloud.env`：`SUPABASE_SERVICE_ROLE_KEY`。

项目地址限定 HTTPS `*.supabase.co`；默认 AI 地址限定 `https://api.siliconflow.cn/v1`，避免把默认密钥发给其它服务。任何请求重定向都会停止。现有账号自定义配置无论启用与否都会使脚本停止，不能用于真实用户账号。

## 实际覆盖

1. 密码登录合成账号，只在内存保留 session。记录旧 AI 元信息；通过 service-role 仅读取该账号配置元信息确认没有配置，不读取密文列。
2. 读取本人固定小队时区，生成 2100×1400、当天 EXIF、明显不同随机几何块的合成学习图片；本机压缩长边 ≤1600、≤2 MiB。
3. 使用随机 UUID 批次与照片，按精确账号/批次检查 media、checkins、media_analysis 和 Storage evidence 前缀均为空。
4. 使用默认同域密钥，将该账号临时设置为唯一不存在的模型，真实 recognize 必须 pending、无 receipt。
5. 再次按精确批次检查四项计数不变，证明确认前零归档写入；不依赖 bootstrap 的可见记录推断。
6. media 确认上传原图及 analysis；断言私有桶、一个原图对象、一个媒体记录、一个临时识别记录、零 checkin。submit_checkin 不传 plan，断言立即 ALL + stamped，尚无 ready 纪要。
7. `finally` 清除本脚本的临时设置，恢复原先空配置后才触发 worker。清除使用 service-role REST DELETE，并用 user_id + 唯一临时模型 + 原 base_url + protocol 原子条件约束；若有人并发修改配置则停止，避免删除他人设置。恢复最多尝试三次，并核对 get_ai_settings 等于初始元信息。
8. 触发 `kind=ai` 并有界轮询 bootstrap。请求观测失败仅计数，继续读业务状态；最终必须保持 stamped 且 memo_status=ready、有摘要，四项最终计数各为一，再确认临时配置已清除。

## 输出和副作用

脚本仅输出固定状态、计数、图片尺寸及脱敏错误码，不输出密钥、JWT、邮箱/密码、photo/checkin/batch ID、data URL、Storage 路径、签名 URL 或供应商错误正文。异常不打印 traceback。结束后将实际结果写入 `output/qa/direct-ai-failure-smoke-result.json`，失败也明确写 failed/interrupted；恢复失败会写 `ai_restore_status=failed`，不能当作通过。

只增加一张合成图片和一条合成打卡，不删除这些记录或任何用户数据。调用全局 AI worker 会处理当时已到期任务，须在既定内测项目执行。脚本正常异常与 Ctrl-C 会执行恢复；进程被 SIGKILL、主机断电或网络持续不可用无法保证 finally 完成，须检查专用账号的 AI 设置并仅清除带本脚本前缀的临时模型，不删除用户数据。

## 离线验证

已对脚本执行 `ast.parse` 语法检查，未导入执行主流程。读取参考 `.local/direct_checkin_smoke.py` 仅为确认接口结构，未读取它引用的配置文件。生产代码保持冻结。
