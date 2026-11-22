import 'package:material_ui/material_ui.dart';

import 'checkin_draft.dart';

/// Preview has no analysis side effects. Only the page's Next action starts AI.
class PhotoPreviewGrid extends StatelessWidget {
  const PhotoPreviewGrid({
    super.key,
    required this.draft,
    required this.enabled,
  });
  final CheckinDraft draft;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 600 ? 3 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 16,
        children: [
          for (final photo in draft.photos)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          photo.original.bytes,
                          width: width,
                          height: 132,
                          fit: BoxFit.cover,
                          cacheWidth: 440,
                          semanticLabel: '待整理照片',
                          errorBuilder: (_, _, _) => SizedBox(
                            width: width,
                            height: 132,
                            child: const Center(child: Text('预览暂不可用')),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton.filled(
                          key: ValueKey('remove-preview-${photo.id}'),
                          tooltip: '移除这张照片',
                          onPressed: enabled ? () => draft.remove(photo) : null,
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (photo.source == 'camera')
                    const Text('实时拍摄')
                  else
                    DropdownButtonFormField<String>(
                      initialValue: photo.source,
                      isExpanded: true,
                      itemHeight: null,
                      decoration: const InputDecoration(labelText: '图片类型'),
                      items: const [
                        DropdownMenuItem(value: 'album', child: Text('普通照片')),
                        DropdownMenuItem(
                          value: 'screenshot',
                          child: Text('记录截图'),
                        ),
                      ],
                      onChanged: enabled
                          ? (value) => draft.changeSource(photo, value!)
                          : null,
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
