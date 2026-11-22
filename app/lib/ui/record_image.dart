import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/media_cache.dart';

class RecordImage extends ConsumerStatefulWidget {
  const RecordImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.variant = 'thumbnail',
    this.version = '1',
  });
  final String url, variant, version;
  final double? width, height;
  final BoxFit fit;
  @override
  ConsumerState<RecordImage> createState() => _RecordImageState();
}

class _RecordImageState extends ConsumerState<RecordImage> {
  Future<File>? _file;
  PrivateMediaCache? _service;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RecordImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.variant != widget.variant ||
        oldWidget.version != widget.version) {
      _load();
    }
  }

  void _load() {
    if (widget.url.startsWith('media:') || widget.url.startsWith('avatar:')) {
      if (_service == null) {
        _service = ref.read(mediaCacheProvider);
        _service!.addListener(_permissionsChanged);
      }
      _file = _service!.get(
        widget.url,
        variant: widget.variant,
        version: widget.version,
      );
    } else {
      _file = null;
    }
  }

  void _permissionsChanged() {
    if (mounted) setState(_load);
  }

  @override
  void dispose() {
    _service?.removeListener(_permissionsChanged);
    super.dispose();
  }

  Widget _error() => SizedBox(
    width: widget.width,
    height: widget.height,
    child: Center(
      child: TextButton.icon(
        onPressed: () => setState(_load),
        icon: const Icon(Icons.refresh),
        label: const Text('点击重试'),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (_file != null) {
      return FutureBuilder<File>(
        future: _file,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _error();
          if (!snapshot.hasData) {
            return SizedBox(
              width: widget.width,
              height: widget.height,
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return Image.file(
            snapshot.data!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            semanticLabel: '打卡照片',
            errorBuilder: (_, _, _) => _error(),
          );
        },
      );
    }
    if (widget.url.startsWith('asset:')) {
      return Image.asset(
        widget.url.substring('asset:'.length),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        semanticLabel: '打卡照片',
        errorBuilder: (_, _, _) => _error(),
      );
    }
    final uri = Uri.tryParse(widget.url);
    if (uri?.scheme == 'file' || widget.url.startsWith('/')) {
      return Image.file(
        File(uri?.scheme == 'file' ? uri!.toFilePath() : widget.url),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        semanticLabel: '打卡照片',
        errorBuilder: (_, _, _) => _error(),
      );
    }
    if (uri?.scheme != 'https' && uri?.scheme != 'http') return _error();
    return Image.network(
      widget.url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      semanticLabel: '打卡照片',
      errorBuilder: (_, _, _) => _error(),
    );
  }
}
