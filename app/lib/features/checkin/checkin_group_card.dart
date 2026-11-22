import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';
import '../../ui/design.dart';
import 'checkin_draft.dart';

class CheckinGroupCard extends StatefulWidget {
  const CheckinGroupCard({
    super.key,
    required this.draft,
    required this.group,
    required this.plans,
    this.enabled = true,
  });
  final CheckinDraft draft;
  final DraftGroup group;
  final List<Plan> plans;
  final bool enabled;

  @override
  State<CheckinGroupCard> createState() => _CheckinGroupCardState();
}

class _CheckinGroupCardState extends State<CheckinGroupCard> {
  late final memo = TextEditingController(
    text: widget.draft.summaryFor(widget.group),
  );
  @override
  void didUpdateWidget(CheckinGroupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = widget.draft.summaryFor(widget.group);
    if (memo.text != value) memo.text = value;
  }

  @override
  void dispose() {
    memo.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<String>> get choices => [
    const DropdownMenuItem(value: '__all__', child: Text('ALL，暂不归类')),
    for (final plan in widget.plans.where((p) => p.isActive))
      DropdownMenuItem(value: plan.id, child: Text(plan.title)),
    if (widget.group.planId != null &&
        !widget.plans.any((p) => p.isActive && p.id == widget.group.planId))
      DropdownMenuItem(
        value: widget.group.planId,
        child: const Text('当前计划（待刷新）'),
      ),
  ];

  String? planId(String? value) => value == '__all__' ? null : value;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return Paper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('group-plan-${group.planId ?? 'all'}'),
            initialValue: group.planId ?? '__all__',
            isExpanded: true,
            itemHeight: null,
            decoration: InputDecoration(
              labelText: '整条记录的计划 · ${group.photos.length} 张',
            ),
            items: choices,
            onChanged: widget.enabled
                ? (value) => widget.draft.assignGroup(group, planId(value))
                : null,
          ),
          const SizedBox(height: 16),
          for (final photo in group.photos) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    photo.analysis?.bytes ?? photo.original.bytes,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    cacheWidth: 220,
                    semanticLabel: '这条记录中的照片',
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 72,
                      height: 72,
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      'photo-plan-${photo.id}-${group.planId ?? 'all'}',
                    ),
                    initialValue: group.planId ?? '__all__',
                    isExpanded: true,
                    itemHeight: null,
                    decoration: const InputDecoration(labelText: '移动这张照片'),
                    items: choices,
                    onChanged: widget.enabled
                        ? (value) =>
                              widget.draft.assignPhoto(photo, planId(value))
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              photo.recognition?.summary.isNotEmpty == true
                  ? photo.recognition!.summary
                  : '摘要待补生成',
            ),
            for (final field in photo.recognition?.fields ?? <MemoField>[])
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  '${field.label}：${field.displayValue} · ${sourceLabel(field.source)}',
                ),
              ),
            const SizedBox(height: 16),
          ],
          TextField(
            key: ValueKey('group-memo-${group.planId ?? 'all'}'),
            controller: memo,
            enabled: widget.enabled,
            minLines: 2,
            maxLines: 5,
            maxLength: 4000,
            decoration: const InputDecoration(labelText: '这条记录的纪要'),
            onChanged: (value) =>
                widget.draft.editGroupSummary(group.planId, value),
          ),
        ],
      ),
    );
  }
}
