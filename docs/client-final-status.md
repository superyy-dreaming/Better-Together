# 客户端收尾结果

## 完成

- DemoRepository 支持本地头像上传（免日期，真实文件保存）、本人头像同步到 team.members、拒绝引用非本人头像路径、删除账号清理头像。新增目录注入仅用于隔离测试。
- Demo 支持分享后周报点赞/取消赞、普通评论；禁止对周报质疑；未分享周报不可互动。`unregister_device` 返回明确 demo 标记，不假装云注册。
- 新生成深绿 #173E2E / 米纸 #F6F3EA 的 BT 字母章。脚本 `scripts/generate_app_icons.py`，系统 Courier New Bold 排字；iOS 19 项尺寸、Android 5 档 mipmap、adaptive foreground/monochrome 已覆盖默认 Flutter 图标。生成过程没有复制或分发字体文件。
- 真实尺寸证明图 `output/brand/icon-size-proof.png` 已查看，384/180/96/48 像素 BT 均可读，无透明 iOS 图标。
- 审查发现 Riverpod AsyncNotifier 会自动保留 previous value，即使设置 AsyncLoading/AsyncError 也保留旧账号数据。已改为 Notifier 显式管理 AsyncValue，使账号切换立即清空，不采用空假数据代替；现有 UI watch/asData/when/notifier 方法接口保持兼容。
- Repository 增加 `currentUserId` 识别用户切换，旧请求回来的身份和 revision 均检查。登出取消 Realtime 和 URL 刷新；鉴权拒绝清除缓存，网络异常仍保留同账号记录并提示。
- 后端照片/头像签名链接有效期实际为 300 秒，客户端每 4 分钟及恢复前台时刷新。错误不伪装空数据。
- 离队/管理成员/删除账号成功后先移除旧快照，即使紧接的读取失败也不继续显示旧权限内容。

## 验证

- `flutter test test/domain_test.dart test/controller_test.dart --no-pub`：23 项通过，含账号退出后的延迟响应、直接换账号、离队后读取中断、头像所有权与清理、周报分享权限、归类/清理/私密草稿 wire、字段只能分配同批一次。
- `dart analyze app/lib/data app/test/domain_test.dart app/test/controller_test.dart`：无问题。
- `flutter test test/widget_test.dart --no-pub`：5 项通过，375/768/1024/1440 宽度大字号导航仍兼容新的显式状态管理。
- 未运行 Flutter build（主线程负责串行平台构建）。

## UI 收尾已完成

PersonAvatar 已支持本地 FileImage 与正式服务 NetworkImage，加载失败保留昵称首字占位。

MemoPage 已接入 BatchDraftCard：本人可查看未归属摘要和字段、选择同批目标、确认公开或私人归属；提交防重复，失败保留草稿并显示重试。已编辑但 classificationPending 仍为 true 时继续显示归类状态和刷新。memo_draft_test.dart 覆盖只有摘要、目标隔离、公开提示、防重复、失败恢复及继续轮询。

当前纪要页独立验证：`memo_draft_test.dart` 6 项通过，三个相关文件 Dart analyze 无问题。375px / 1.4x 字号的深浅色顶端和公开确认截图已实际查看，文件为 `output/qa/memo-draft-{light,dark}-{top,confirm}.png`；使用本机中文字体做组件渲染，属于 Widget 渲染检查，不替代原生设备测试。

主线程最终全量检查：Flutter analyze 无问题，40 项 Flutter 测试通过，详见 output/qa/flutter-analyze.log 和 flutter-test.log。

## 权限审查边界

Realtime publication 已由后端补齐，仍由表 RLS 过滤。客户端只根据事件重新调用授权后的 bootstrap，不把事件 payload 合并成可信可见数据。退出/剔除通过 membership UPDATE 触发同步；已有签名 URL 是 bearer URL，权限收回后其服务器有效期最多还剩 300 秒，此限制需在真实 Storage 烟测中验证。

## 使用依据

OJO / 项目 DESIGN.md 的纸面章方向优先；ui-ux-pro-max 搜索的默认营销模板与本应用不匹配，未采用其自动配色/布局。使用其可读性要求以及 Impeccable polish/craft-floor 检查小尺寸资产。无 appledesign skill，以已加载平台 guidance 和 Apple 官方能力约束为替代；图标无任何新增交互行为。

## 审查修复接口补齐

- Checkin 新增 `classificationPending`、`unassignedFields`、`unassignedSummary`，精确对应 wire 的三个 snake_case 字段；CheckinPhoto 保留主线程已添加的 `cleanupStatus`。
- UI 已在 `memoStatus == 'pending' || classificationPending` 时继续监听归类状态，不因为用户编辑把 memo 变 ready 就终止。
- UI 的私密草稿入口已使用 `unassignedFields.isNotEmpty || unassignedSummary.isNotEmpty`，仅有摘要也可归属；调用 `assign_batch_fields` 时给原卡 ID 和同 batch 目标卡 ID。不会把摘要默认复制到所有子卡。
- Demo `assign_batch_fields` 校验本人、同批、非空草稿、目标品类，按 key 合并一次后清空原草稿；保留手填来源，不伪造 AI。编辑纪要不会清掉 `classification_pending`，演示新提交不排远程任务所以显式 false。
- Demo 原图为本地同步删除，成功回 `{deleted:true,cleanup_status:'done'}`，不制造不存在的后台 pending。生产 pending wire 测试确认空 URL 与清理中状态可共存。
- Supabase Realtime 订阅新增 `report_interactions`，保证队友对周报的回应触发刷新。
