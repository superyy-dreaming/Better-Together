import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models.dart';
import '../../domain/invitation.dart';
import 'invite_scanner_page.dart';
import '../../ui/design.dart';
import '../../ui/state_view.dart';

class InvitePage extends ConsumerStatefulWidget {
  const InvitePage({super.key, this.token});
  final String? token;
  @override
  ConsumerState<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends ConsumerState<InvitePage> {
  final name = TextEditingController();
  late final code = TextEditingController(text: widget.token);
  String zone = 'Asia/Shanghai';
  JsonMap? invitation;
  bool busy = false;
  String? joinIssue;
  String? scanMessage;

  @override
  void didUpdateWidget(covariant InvitePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.token != oldWidget.token && widget.token != null) {
      code.text = widget.token!;
      joinIssue = null;
      scanMessage = null;
    }
  }

  Future<void> scanInvitation() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      final result = await ref.read(inviteScannerProvider)(context);
      if (!mounted || result == null) return;
      setState(() {
        code.text = result;
        joinIssue = null;
        scanMessage = '已识别邀请码，点击「确认加入」继续。';
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> joinTeam() async {
    if (busy) return;
    final token = invitationToken(code.text);
    if (token == null) {
      setState(() => joinIssue = '请输入 8 位邀请码，或粘贴完整的小队邀请链接。');
      return;
    }
    setState(() {
      busy = true;
      joinIssue = null;
    });
    final result = await runAction(context, ref, 'join_team', {'token': token});
    if (!mounted) return;
    setState(() => busy = false);
    if (result != null) feedback(context, '已加入小队');
  }

  Future<void> generateInvitation() async {
    if (busy) return;
    setState(() => busy = true);
    final result = await runAction(context, ref, 'create_invite');
    if (!mounted) return;
    setState(() {
      busy = false;
      if (result != null) invitation = result;
    });
  }

  @override
  void dispose() {
    name.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotView(
    builder: (s) => Scaffold(
      appBar: AppBar(title: Text(s.team == null ? '找一个同行的人' : '小队与邀请')),
      body: PageBody(
        children: [
          Text(
            '各自的小目标，\n共同的每一天。',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 14),
          const Text('小队只共享陪伴，不要求相同目标。最多 5 人，记录仅在小队里可见。'),
          const SizedBox(height: 24),
          if (s.team == null) ...[
            const SectionTitle('加入朋友的小队'),
            FilledButton.icon(
              key: const ValueKey('invite-scan'),
              onPressed: busy ? null : scanInvitation,
              icon: const Icon(CupertinoIcons.qrcode_viewfinder),
              label: const Text('扫码加入'),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('invite-code'),
              controller: code,
              enabled: !busy,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => joinTeam(),
              onChanged: (_) => setState(() {
                joinIssue = null;
                scanMessage = null;
              }),
              decoration: InputDecoration(
                labelText: '邀请码或邀请链接',
                helperText: '8 位字母数字，不区分大小写；也支持原有邀请链接。',
                helperMaxLines: 3,
                errorText: joinIssue,
                errorMaxLines: 3,
              ),
            ),
            if (scanMessage != null) ...[
              const SizedBox(height: 8),
              Semantics(liveRegion: true, child: Text(scanMessage!)),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('invite-join'),
              onPressed: busy ? null : joinTeam,
              child: Text(busy ? '正在处理' : '确认加入'),
            ),
            const SectionTitle('创建新小队'),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '小队名字'),
              maxLength: 30,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: zone,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '小队时区，创建后固定'),
              items: const [
                DropdownMenuItem(
                  value: 'Asia/Shanghai',
                  child: Text('北京时间 · Asia/Shanghai'),
                ),
                DropdownMenuItem(
                  value: 'Asia/Singapore',
                  child: Text('新加坡 · Asia/Singapore'),
                ),
                DropdownMenuItem(
                  value: 'Asia/Tokyo',
                  child: Text('东京 · Asia/Tokyo'),
                ),
                DropdownMenuItem(
                  value: 'Europe/London',
                  child: Text('伦敦 · Europe/London'),
                ),
                DropdownMenuItem(
                  value: 'America/New_York',
                  child: Text('纽约 · America/New_York'),
                ),
                DropdownMenuItem(
                  value: 'America/Los_Angeles',
                  child: Text('洛杉矶 · America/Los_Angeles'),
                ),
              ],
              onChanged: (v) => setState(() => zone = v!),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (busy) return;
                      if (name.text.trim().isEmpty) {
                        feedback(context, '先给小队起个名字');
                        return;
                      }
                      setState(() => busy = true);
                      await runAction(context, ref, 'create_team', {
                        'name': name.text.trim(),
                        'timezone': zone,
                      });
                      if (mounted) setState(() => busy = false);
                    },
              child: const Text('创建小队'),
            ),
          ],
          if (s.team != null) ...[
            Paper(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.team!.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('${s.team!.members.length}/5 人 · ${s.team!.timezone}'),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('invite-generate'),
                    onPressed: busy ? null : generateInvitation,
                    child: Text(busy ? '正在生成' : '生成邀请'),
                  ),
                ],
              ),
            ),
            if (invitation != null) ...[
              const SizedBox(height: 20),
              Center(
                child: QrImageView(
                  data: stringValue(invitation!['url']),
                  semanticsLabel: '小队邀请二维码，请队友使用扫码加入',
                  backgroundColor: Colors.white,
                  size: 210,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: SelectableText(
                  displayInvitationCode(stringValue(invitation!['token'])),
                  key: const ValueKey('invite-display-code'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '邀请码 7 天内有效。让朋友扫码，或输入上方邀请码。',
                textAlign: TextAlign.center,
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: stringValue(invitation!['token'])),
                  );
                  if (context.mounted) feedback(context, '邀请码已复制');
                },
                icon: const Icon(CupertinoIcons.doc_on_doc),
                label: const Text('复制邀请码'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    sharePositionOrigin: const Rect.fromLTWH(20, 80, 300, 44),
                    text:
                        '来 Better Together，一起坚持自己的小目标。\n邀请码：${displayInvitationCode(stringValue(invitation!['token']))}\n${invitation!['url']}',
                  ),
                ),
                child: const Text('分享邀请链接'),
              ),
            ],
            const SectionTitle('成员'),
            ...s.team!.members.map(
              (m) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: PersonAvatar(m.nickname, url: m.avatarUrl),
                title: Text(m.nickname),
                trailing:
                    s.team!.ownerId == s.profile.id && m.id != s.profile.id
                    ? TextButton(
                        onPressed: () async {
                          if (await confirmAction(
                                context,
                                '移除 ${m.nickname}？',
                                '对方的历史记录将改为仅本人可见。',
                              ) &&
                              context.mounted) {
                            await runAction(context, ref, 'manage_team', {
                              'operation': 'remove',
                              'member_id': m.id,
                            });
                          }
                        },
                        child: const Text('移除'),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 24),
            if (s.team!.ownerId == s.profile.id)
              OutlinedButton(
                onPressed: () async {
                  if (await confirmAction(
                        context,
                        '解散小队？',
                        '所有成员的历史记录将保留为本人私密记录。',
                        accept: '解散小队',
                      ) &&
                      context.mounted) {
                    await runAction(context, ref, 'manage_team', {
                      'operation': 'dissolve',
                    });
                  }
                },
                child: const Text('解散小队'),
              )
            else
              OutlinedButton(
                onPressed: () async {
                  if (await confirmAction(
                        context,
                        '退出小队？',
                        '你的历史记录会保留，只有你自己可见。',
                        accept: '退出小队',
                      ) &&
                      context.mounted) {
                    await runAction(context, ref, 'leave_team');
                  }
                },
                child: const Text('退出小队'),
              ),
          ],
        ],
      ),
    ),
  );
}
