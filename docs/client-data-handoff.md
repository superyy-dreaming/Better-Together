# 客户端数据层交接

## 已验证

- `app/lib/domain/`：共享模型及固定时区、计划频率、质疑阈值、补卡、连续记录、23:30 逾期封顶规则。
- `app/lib/data/`：Supabase API、媒体上传、邮箱 OTP、Apple 登录、Riverpod 状态、明确开启的本地演示。
- Realtime 只触发重新读取，使用服务端快照作为事实来源；断连保留已有记录，恢复后同步。旧读取结果不会覆盖较新的快照。
- 本地演示不伪造 AI、截图 OCR 或远程通信，动作被拒绝时回滚内存状态。
- `flutter test test/domain_test.dart test/controller_test.dart`：16 项通过。
- `flutter analyze lib/data lib/domain test/domain_test.dart test/controller_test.dart`：无问题。

## 主线程联调清单

- Today 连续天数使用 `p.streak ?? streakForPlan(...)`。服务端历史窗口有限，正式模式必须使用服务端统计。
- Demo 的照片 URL 为应用支持目录文件路径，Memo 图片需要区分本地文件与 HTTPS。
- 服务端应将 `profiles`、`teams`、`team_members`、`plans`、`checkins`、`media`、`interactions`、`overdue_feed`、`pokes`、`reports`、`notifications` 加入 Realtime publication，保留 RLS。
- `team.streak` 应由服务端聚合，不能返回常量 0。
- 未进行真实凭据的 Supabase、邮件、Apple 登录或媒体服务联调。
