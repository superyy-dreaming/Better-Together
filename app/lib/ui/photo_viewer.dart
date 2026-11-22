import 'package:material_ui/material_ui.dart';

import '../domain/models.dart';
import 'record_image.dart';

void showPhotoViewer(
  BuildContext context,
  List<CheckinPhoto> photos,
  int index,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _PhotoViewer(photos: photos, index: index),
    ),
  );
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.index});
  final List<CheckinPhoto> photos;
  final int index;
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController pages = PageController(initialPage: widget.index);
  late int current = widget.index;
  bool zoomed = false;
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text('${current + 1} / ${widget.photos.length}'),
    ),
    body: SafeArea(
      child: PageView.builder(
        controller: pages,
        physics: zoomed ? const NeverScrollableScrollPhysics() : null,
        onPageChanged: (i) => setState(() {
          current = i;
          zoomed = false;
        }),
        itemCount: widget.photos.length,
        itemBuilder: (_, i) => _ZoomPhoto(
          photo: widget.photos[i],
          onSwipe: (direction) {
            final target = (current + direction).clamp(
              0,
              widget.photos.length - 1,
            );
            if (target != current) {
              pages.animateToPage(
                target,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOut,
              );
            }
          },
          onZoom: (value) {
            if (i == current && zoomed != value) setState(() => zoomed = value);
          },
        ),
      ),
    ),
  );
}

class _ZoomPhoto extends StatefulWidget {
  const _ZoomPhoto({
    required this.photo,
    required this.onZoom,
    required this.onSwipe,
  });
  final CheckinPhoto photo;
  final ValueChanged<bool> onZoom;
  final ValueChanged<int> onSwipe;
  @override
  State<_ZoomPhoto> createState() => _ZoomPhotoState();
}

class _ZoomPhotoState extends State<_ZoomPhoto> {
  final transformation = TransformationController();
  TapDownDetails? tap;
  double horizontalDrag = 0;
  bool multiTouch = false;
  @override
  void initState() {
    super.initState();
    transformation.addListener(_changed);
  }

  void _changed() =>
      widget.onZoom(transformation.value.getMaxScaleOnAxis() > 1.02);
  @override
  void dispose() {
    transformation.removeListener(_changed);
    transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => GestureDetector(
      onDoubleTapDown: (details) => tap = details,
      onDoubleTap: () {
        if (transformation.value.getMaxScaleOnAxis() > 1.02) {
          transformation.value = Matrix4.identity();
        } else {
          final position =
              tap?.localPosition ?? Offset(box.maxWidth / 2, box.maxHeight / 2);
          transformation.value = Matrix4.identity()
            ..translateByDouble(-position.dx * 2, -position.dy * 2, 0, 1)
            ..scaleByDouble(3, 3, 1, 1);
        }
      },
      child: InteractiveViewer(
        onInteractionStart: (_) {
          horizontalDrag = 0;
          multiTouch = false;
        },
        onInteractionUpdate: (details) {
          multiTouch = multiTouch || details.pointerCount > 1;
          if (!multiTouch && transformation.value.getMaxScaleOnAxis() <= 1.02) {
            horizontalDrag += details.focalPointDelta.dx;
          }
        },
        onInteractionEnd: (_) {
          // InteractiveViewer owns the scale arena even at 1x. Pass its
          // unzoomed, single-finger horizontal gesture to the page controller.
          if (!multiTouch &&
              transformation.value.getMaxScaleOnAxis() <= 1.02 &&
              horizontalDrag.abs() > 48) {
            widget.onSwipe(horizontalDrag < 0 ? 1 : -1);
          }
        },
        transformationController: transformation,
        minScale: 1,
        maxScale: 5,
        child: SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
          child: RecordImage(
            widget.photo.url,
            fit: BoxFit.contain,
            variant: 'original',
            width: box.maxWidth,
            height: box.maxHeight,
          ),
        ),
      ),
    ),
  );
}
