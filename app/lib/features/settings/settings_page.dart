import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models.dart';

import '../../data/app_controller.dart';
import '../../ui/design.dart';
import '../../ui/bear_avatar.dart';
import '../../ui/app_appearance.dart';
import '../../ui/state_view.dart';
import '../../platform/providers.dart';
import '../../platform/push_service.dart';
import '../../platform/photo_preparation.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool busy = false;

  Future<void> resetDemoShowcase() async {
    if (!await confirmAction(
      context,
      '重置为讲解场景？',
      '这会替换本机演示数据，载入 20 张合成测试照片及对应的 5 人小队、计划、纪要、互动和周报。不会影响正式账号或云端数据。',
      accept: '重置演示数据',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    await runAction(context, ref, 'reset_demo_showcase');
    if (mounted) setState(() => busy = false);
  }

  Future<void> changeAvatar() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('挑一只小熊陪你', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(
                    12,
                    (i) => Semantics(
                      label: '第 ${i + 1} 款小熊头像',
                      button: true,
                      child: InkWell(
                        onTap: () => Navigator.pop(ctx, bearPreset(i)),
                        child: BearAvatar(index: i, size: 64),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('从相册选择照片'),
                  onTap: () => Navigator.pop(ctx, 'photo'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice != 'photo') {
      setState(() => busy = true);
      await runAction(context, ref, 'save_profile', {'avatar_url': choice});
      if (mounted) setState(() => busy = false);
      return;
    }
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (photo == null || !mounted) return;
      setState(() => busy = true);
      final prepared = await preparePickedPhoto(photo.path);
      final avatarBytes = await prepareAvatar(prepared.bytes);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认头像'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: Image.memory(avatarBytes, width: 180, height: 180),
              ),
              const SizedBox(height: 12),
              const Text('已居中裁切。取消可重新选择。'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('使用这张'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final uploaded = await ref
          .read(appControllerProvider.notifier)
          .upload(
            PhotoUpload(
              bytes: avatarBytes,
              filename: 'avatar.jpg',
              source: 'avatar',
              batchId: const Uuid().v4(),
              contentType: 'image/jpeg',
            ),
          );
      if (!mounted) return;
      await runAction(context, ref, 'save_profile', {
        'avatar_url': uploaded.path,
      });
    } catch (e) {
      if (mounted) feedback(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> rename(String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('大家怎么称呼你'),
        content: TextField(
          controller: controller,
          maxLength: 30,
          decoration: const InputDecoration(labelText: '昵称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      await runAction(context, ref, 'save_profile', {'nickname': result});
    }
  }

  @override
  Widget build(BuildContext context) => SnapshotView(
    builder: (s) => Scaffold(
      appBar: AppBar(title: const Text('我的与设置')),
      body: PageBody(
        children: [
          Paper(
            child: Row(
              children: [
                PersonAvatar(
                  s.profile.nickname,
                  url: s.profile.avatarUrl,
                  userId: s.profile.id,
                  size: 64,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.profile.nickname,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        s.timezone,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '修改昵称',
                  onPressed: () => rename(s.profile.nickname),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: busy ? null : changeAvatar,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(busy ? '正在保存头像' : '更换头像'),
          ),
          const SectionTitle('外观与体验'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.palette_outlined),
            title: const Text('界面外观'),
            subtitle: Text(
              ref.watch(appearanceStatusProvider).error ??
                  ref.watch(appearanceProvider).label,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/appearance'),
          ),
          const SectionTitle('按自己的节奏'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('历史记录与补卡'),
            subtitle: Text('本月剩余 ${s.profile.makeupRemaining} 张补卡'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/history'),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('暂停本周'),
            subtitle: const Text('本周无需打卡，连续记录冻结，不增加天数。'),
            value: s.profile.pausedWeek,
            onChanged: busy
                ? null
                : (value) async {
                    setState(() => busy = true);
                    await runAction(context, ref, 'pause_week', {
                      'paused': value,
                    });
                    if (mounted) setState(() => busy = false);
                  },
          ),
          const SectionTitle('AI 与纪要'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tune_rounded),
            title: const Text('AI 识别'),
            subtitle: const Text('选择默认服务，或连接自己的 AI 接口'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/ai'),
          ),
          const SectionTitle('通知偏好'),
          ValueListenableBuilder<PushState>(
            valueListenable: ref.watch(pushServiceProvider).state,
            builder: (context, state, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('系统通知'),
              subtitle: Text(state.message),
              trailing: TextButton(
                onPressed: () =>
                    ref.read(pushServiceProvider).requestPermission(),
                child: const Text('开启'),
              ),
            ),
          ),
          const Text('这里控制提醒方式。应用内通知会保留重要记录。'),
          ...const {
            'all': '接收推送通知',
            'poke': '队友戳一下',
            'overdue': '计划逾期',
            'report': '每周周报',
            'interaction': '点赞与评论',
            'challenge': '打卡质疑',
          }.entries.map(
            (e) => SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(e.value),
              value: s.profile.notificationPreferences[e.key] ?? true,
              onChanged: busy
                  ? null
                  : (value) async {
                      setState(() => busy = true);
                      await runAction(context, ref, 'save_profile', {
                        'notification_preferences': {
                          ...s.profile.notificationPreferences,
                          e.key: value,
                        },
                      });
                      if (mounted) setState(() => busy = false);
                    },
            ),
          ),
          const SectionTitle('数据与隐私'),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.favorite_border),
            title: Text('健康数据'),
            subtitle: Text('当前版本尚未接入。运动时长来自计时、截图或手动填写。'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('照片与隐私说明'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/privacy'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('小队与成员管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/invite'),
          ),
          if (ref.read(repositoryProvider).isDemo) ...[
            const SectionTitle('演示场景'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('重置为讲解场景'),
              subtitle: const Text('载入 20 张测试照片与对应的纪要、小队和周报'),
              onTap: busy ? null : resetDemoShowcase,
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    if (!await confirmAction(
                      context,
                      '退出登录？',
                      '云端记录会保留，再次登录即可继续。',
                    )) {
                      return;
                    }
                    if (!mounted) return;
                    try {
                      await ref.read(pushServiceProvider).stop();
                      await ref.read(repositoryProvider).signOut();
                    } catch (e) {
                      if (context.mounted) feedback(context, e.toString());
                    }
                  },
            child: const Text('退出登录'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    if (!await confirmAction(
                      context,
                      '删除账户和全部个人数据？',
                      '这会删除账号、原图、计划和纪要，无法恢复。你在小队的成员关系也将移除。',
                      accept: '删除账户',
                    )) {
                      return;
                    }
                    if (!context.mounted) return;
                    setState(() => busy = true);
                    await runAction(context, ref, 'delete_account', {
                      'confirmation': 'DELETE',
                    });
                    if (mounted) setState(() => busy = false);
                  },
            child: Text(
              '删除账户',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Better Together · 内测版 1.0.0',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('照片与隐私')),
    body: const PageBody(
      children: [
        SectionTitle('谁能看见'),
        Text(
          '私密计划仅你自己可见。小队计划与相关打卡对当前队友可见。退出或解散小队后，历史记录只对作者本人可见。分享个人周报长图前，请确认其中的内容可以公开。',
        ),
        SectionTitle('照片如何保存'),
        Text('原图存放在私有存储中，访问链接短期有效。原图默认保留到你主动删除；可在每条纪要中逐张删除，或通过删除账户移除全部个人数据。'),
        SectionTitle('AI 如何参与'),
        Text(
          '照片会用于分类和生成纪要，结果可能有误。你可以修改摘要、数据和归类。热量是估算区间；缺少来源的运动时长与消耗显示为未记录。AI 暂时不可用时，已盖章状态仍然有效。',
        ),
        SectionTitle('服务与数据位置'),
        Text(
          '主要数据保存在新加坡区域的 Supabase。默认使用运营方配置的 AI 服务；启用自定义 AI 后，待识别照片及生成纪要、个人周报所需的内容会发送到你指定的服务。你可以在设置中的“AI 识别”查看、停用或清除自定义配置。真实照片内测须在运营方完成连接验证及隐私、跨境数据说明后开放。本页为产品内数据说明，正式发布前需要补充运营主体、联系方式和适用的完整隐私政策。',
        ),
      ],
    ),
  );
}
