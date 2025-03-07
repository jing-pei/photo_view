import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_view/photo_view.dart'
    show
        PhotoViewHeroAttributes,
        PhotoViewImageScaleEndCallback,
        PhotoViewImageScaleStartCallback,
        PhotoViewImageScaleUpdateCallback,
        PhotoViewImageTapDownCallback,
        PhotoViewImageTapUpCallback,
        PhotoViewScaleState,
        ScaleStateCycle;
import 'package:photo_view/src/controller/photo_view_controller.dart';
import 'package:photo_view/src/controller/photo_view_controller_delegate.dart';
import 'package:photo_view/src/controller/photo_view_scalestate_controller.dart';
import 'package:photo_view/src/core/photo_view_gesture_detector.dart';
import 'package:photo_view/src/core/photo_view_hit_corners.dart';
import 'package:photo_view/src/utils/photo_view_utils.dart';

const _defaultDecoration = const BoxDecoration(
  color: const Color.fromRGBO(0, 0, 0, 0.0),
);

/// Internal widget in which controls all animations lifecycle, core responses
/// to user gestures, updates to  the controller state and mounts the entire PhotoView Layout
class PhotoViewCore extends StatefulWidget {
  const PhotoViewCore({
    Key? key,
    required this.imageProvider,
    required this.backgroundDecoration,
    required this.gaplessPlayback,
    required this.heroAttributes,
    required this.enableRotation,
    required this.onTapUp,
    required this.onTapDown,
    required this.onScaleUpdate,
    required this.onScaleStart,
    required this.onScaleEnd,
    required this.gestureDetectorBehavior,
    required this.controller,
    required this.scaleBoundaries,
    required this.scaleStateCycle,
    required this.scaleStateController,
    required this.basePosition,
    required this.tightMode,
    required this.filterQuality,
    this.canScale = true,
  })  : customChild = null,
        super(key: key);

  const PhotoViewCore.customChild({
    Key? key,
    required this.customChild,
    required this.backgroundDecoration,
    required this.heroAttributes,
    required this.enableRotation,
    required this.onTapUp,
    required this.onTapDown,
    required this.onScaleUpdate,
    required this.onScaleStart,
    required this.onScaleEnd,
    required this.gestureDetectorBehavior,
    required this.controller,
    required this.scaleBoundaries,
    required this.scaleStateCycle,
    required this.scaleStateController,
    required this.basePosition,
    required this.tightMode,
    required this.filterQuality,
    this.canScale = true,
  })  : imageProvider = null,
        gaplessPlayback = false,
        super(key: key);

  final Decoration? backgroundDecoration;
  final ImageProvider? imageProvider;
  final bool gaplessPlayback;
  final PhotoViewHeroAttributes? heroAttributes;
  final bool enableRotation;
  final Widget? customChild;

  final PhotoViewControllerBase? controller;
  final PhotoViewScaleStateController? scaleStateController;
  final ScaleBoundaries scaleBoundaries;
  final ScaleStateCycle scaleStateCycle;
  final Alignment basePosition;

  final PhotoViewImageTapUpCallback? onTapUp;
  final PhotoViewImageTapDownCallback? onTapDown;
  final PhotoViewImageScaleStartCallback? onScaleStart;
  final PhotoViewImageScaleUpdateCallback? onScaleUpdate;
  final PhotoViewImageScaleEndCallback? onScaleEnd;

  final HitTestBehavior? gestureDetectorBehavior;
  final bool tightMode;

  final FilterQuality filterQuality;
  final bool canScale;

  @override
  State<StatefulWidget> createState() {
    return PhotoViewCoreState();
  }

  bool get hasCustomChild => customChild != null;
}

class PhotoViewCoreState extends State<PhotoViewCore>
    with
        TickerProviderStateMixin,
        PhotoViewControllerDelegate,
        HitCornersDetector {
  Offset? _normalizedPosition;
  double? _scaleBefore;
  double? _rotationBefore;

  late AnimationController _scaleAnimationController;
  late Animation<double> _scaleAnimation;

  late AnimationController _positionAnimationController;
  late Animation<Offset> _positionAnimation;

  late AnimationController _rotationAnimationController;
  late Animation<double> _rotationAnimation;

  PhotoViewHeroAttributes? get heroAttributes => widget.heroAttributes;

  ScaleBoundaries? cachedScaleBoundaries;

  void handleScaleAnimation() {
    scale = _scaleAnimation.value;
  }

  void handlePositionAnimate() {
    controller!.position = _positionAnimation.value;
  }

  void handleRotationAnimation() {
    controller!.rotation = _rotationAnimation.value;
  }

  void onScaleStart(ScaleStartDetails details) {
    _rotationBefore = controller!.rotation;
    _scaleBefore = scale;
    _normalizedPosition = details.focalPoint - controller!.position!;
    _scaleAnimationController.stop();
    _positionAnimationController.stop();
    _rotationAnimationController.stop();

    widget.onScaleStart
        ?.call(context, details, _normalizedPosition, controller!.value);
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    final double newScale = _scaleBefore! * details.scale;
    final Offset delta = details.focalPoint - _normalizedPosition!;

    updateScaleStateFromNewScale(newScale);

//    print('position:${clampPosition(position: delta * details.scale)} cornersY:${cornersY(scale: details.scale).max}');
    if (widget.canScale)
      updateMultiple(
        scale: newScale,
        position: clampPosition(position: delta * details.scale),
        rotation: _rotationBefore! + details.rotation,
        rotationFocusPoint: details.focalPoint,
      );
    widget.onScaleUpdate?.call(context, details, delta, controller!.value);
  }

  void onScaleEnd(ScaleEndDetails details) {
    final double? _scale = scale;
    final Offset? _position = controller!.position;
    final double? maxScale = scaleBoundaries.maxScale;
    final double minScale = scaleBoundaries.minScale;

    widget.onScaleEnd?.call(context, details, _position, controller!.value);

    if (!widget.canScale) return;
    //animate back to maxScale if gesture exceeded the maxScale specified
    if (_scale! > maxScale!) {
      final double scaleComebackRatio = maxScale / _scale;
      animateScale(_scale, maxScale);
      final Offset clampedPosition = clampPosition(
        position: _position! * scaleComebackRatio,
        scale: maxScale,
      );
      animatePosition(_position, clampedPosition);
      return;
    }

    //animate back to minScale if gesture fell smaller than the minScale specified
    if (_scale < minScale) {
      final double scaleComebackRatio = minScale / _scale;
      animateScale(_scale, minScale);
      animatePosition(
        _position,
        clampPosition(
          position: _position! * scaleComebackRatio,
          scale: minScale,
        ),
      );
      return;
    }
    // get magnitude from gesture velocity
    final double magnitude = details.velocity.pixelsPerSecond.distance;

    // animate velocity only if there is no scale change and a significant magnitude
    print(magnitude);
    if (_scaleBefore! / _scale == 1.0 && magnitude >= 400.0) {
      final Offset direction = details.velocity.pixelsPerSecond / magnitude;
      animatePosition(
        _position,
        clampPosition(position: _position! + direction * magnitude * 0.5),
      );
    }
  }

  void onDoubleTap() {
    nextScaleState();
  }

  void animateScale(double? from, double? to) {
    _scaleAnimation = Tween<double>(
      begin: from,
      end: to,
    ).animate(_scaleAnimationController);
    _scaleAnimationController
      ..value = 0.0
      ..fling(velocity: 0.4);
  }

  void animatePosition(Offset? from, Offset to) {
    _positionAnimation = Tween<Offset>(begin: from, end: to).animate(
        CurvedAnimation(
            parent: _positionAnimationController, curve: Curves.easeOutCirc));
    _positionAnimationController
      ..value = 0.0
      ..forward();
  }

  void animateRotation(double? from, double to) {
    _rotationAnimation = Tween<double>(begin: from, end: to)
        .animate(_rotationAnimationController);
    _rotationAnimationController
      ..value = 0.0
      ..fling(velocity: 0.4);
  }

  void onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      onAnimationStatusCompleted();
    }
  }

  /// Check if scale is equal to initial after scale animation update
  void onAnimationStatusCompleted() {
    if (scaleStateController!.scaleState != PhotoViewScaleState.initial &&
        scale == scaleBoundaries.initialScale) {
      scaleStateController!.setInvisibly(PhotoViewScaleState.initial);
    }
  }

  @override
  void initState() {
    super.initState();
    _scaleAnimationController = AnimationController(vsync: this)
      ..addListener(handleScaleAnimation);
    _scaleAnimationController.addStatusListener(onAnimationStatus);

    _positionAnimationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..addListener(handlePositionAnimate);

    _rotationAnimationController = AnimationController(vsync: this)
      ..addListener(handleRotationAnimation);
    startListeners();
    addAnimateOnScaleStateUpdate(animateOnScaleStateUpdate);

    cachedScaleBoundaries = widget.scaleBoundaries;

    setState(() {});
  }

  void animateOnScaleStateUpdate(double? prevScale, double? nextScale) {
    animateScale(prevScale, nextScale);
    animatePosition(controller!.position, Offset.zero);
    animateRotation(controller!.rotation, 0.0);
  }

  @override
  void dispose() {
    _scaleAnimationController.removeStatusListener(onAnimationStatus);
    _scaleAnimationController.dispose();
    _positionAnimationController.dispose();
    _rotationAnimationController.dispose();
    super.dispose();
  }

  void onTapUp(TapUpDetails details) {
    widget.onTapUp?.call(context, details, controller!.value);
  }

  void onTapDown(TapDownDetails details) {
//    widget.onTapDown?.call(context, details, controller.value);
    _positionAnimationController.stop();
  }

  @override
  Widget build(BuildContext context) {
    // Check if we need a recalc on the scale
    if (widget.scaleBoundaries != cachedScaleBoundaries) {
      markNeedsScaleRecalc = true;
      cachedScaleBoundaries = widget.scaleBoundaries;
    }

    return StreamBuilder(
        stream: controller!.outputStateStream,
        initialData: controller!.prevValue,
        builder: (
          BuildContext context,
          AsyncSnapshot<PhotoViewControllerValue?> snapshot,
        ) {
          if (snapshot.hasData) {
            final PhotoViewControllerValue value = snapshot.data!;
            final useImageScale = widget.filterQuality != FilterQuality.none;
            final computedScale = useImageScale ? 1.0 : scale;

            final matrix = Matrix4.identity()
              ..translate(value.position!.dx, value.position!.dy)
              ..scale(computedScale);
            if (widget.enableRotation) {
              matrix..rotateZ(value.rotation!);
            }
//            print('position: ${value.position.dy} ,'
//                'child: ${ (scaleBoundaries.childSize.height * computedScale - scaleBoundaries.outerSize.height ) / 2}');

            final Widget customChildLayout = CustomSingleChildLayout(
              delegate: _CenterWithOriginalSizeDelegate(
                scaleBoundaries.childSize,
                basePosition,
                useImageScale,
              ),
              child: _buildHero(),
            );
            return Listener(
                onPointerSignal: _handlePointerSignal,
                child: PhotoViewGestureDetector(
                  child: Container(
                    constraints: widget.tightMode
                        ? BoxConstraints.tight(
                            scaleBoundaries.childSize! * scale!)
                        : null,
                    child: Center(
                      child: Transform(
                        child: customChildLayout,
                        transform: matrix,
                        alignment: basePosition,
                      ),
                    ),
                    decoration:
                        widget.backgroundDecoration ?? _defaultDecoration,
                  ),
                  onDoubleTap: nextScaleState,
                  onScaleStart: onScaleStart,
                  onScaleUpdate: onScaleUpdate,
                  onScaleEnd: onScaleEnd,
                  hitDetector: this,
                  onTapUp: widget.onTapUp == null ? null : onTapUp,
                  onTapDown: onTapDown,
                ));
          } else {
            return Container();
          }
        });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && event.kind == PointerDeviceKind.mouse) {
      final double? _scale = scale;
      final double? maxScale = scaleBoundaries.maxScale;
      final double? minScale = scaleBoundaries.minScale;
      final bool zoom = event.scrollDelta.dy < 0;
      double nextScale = zoom ? 1.2 : 0.8;
      if (zoom) {
        if (_scale == maxScale!) {
          return;
        }
        if (_scale! * nextScale > maxScale) {
          nextScale = maxScale / _scale;
        }
      } else {
        if (_scale == minScale!) {
          return;
        }
        if (_scale! * nextScale < minScale) {
          nextScale = minScale / _scale;
        }
      }
      onScaleStart(ScaleStartDetails(focalPoint: event.position));
      onScaleUpdate(ScaleUpdateDetails(
          focalPoint: event.position,
          scale: nextScale,
          focalPointDelta: Offset.zero));
      onScaleEnd(ScaleEndDetails());
    }
  }

  Widget? _buildHero() {
    return heroAttributes != null
        ? Hero(
            tag: heroAttributes!.tag,
            createRectTween: heroAttributes!.createRectTween,
            flightShuttleBuilder: heroAttributes!.flightShuttleBuilder,
            placeholderBuilder: heroAttributes!.placeholderBuilder,
            transitionOnUserGestures: heroAttributes!.transitionOnUserGestures,
            child: _buildChild()!,
          )
        : _buildChild();
  }

  Widget? _buildChild() {
    return widget.hasCustomChild
        ? widget.customChild
        : Image(
            image: widget.imageProvider!,
            gaplessPlayback: widget.gaplessPlayback,
            filterQuality: widget.filterQuality,
            width: scaleBoundaries.childSize!.width * scale!,
            fit: BoxFit.contain,
          );
  }
}

class _CenterWithOriginalSizeDelegate extends SingleChildLayoutDelegate {
  const _CenterWithOriginalSizeDelegate(
    this.subjectSize,
    this.basePosition,
    this.useImageScale,
  );

  final Size? subjectSize;
  final Alignment basePosition;
  final bool useImageScale;

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final childWidth = useImageScale ? childSize.width : subjectSize!.width;
    final childHeight = useImageScale ? childSize.height : subjectSize!.height;

    final halfWidth = (size.width - childWidth) / 2;
    final halfHeight = (size.height - childHeight) / 2;

    final double offsetX = halfWidth * (basePosition.x + 1);
    final double offsetY = halfHeight * (basePosition.y + 1);
    return Offset(offsetX, offsetY);
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return useImageScale
        ? const BoxConstraints()
        : BoxConstraints.tight(subjectSize!);
  }

  @override
  bool shouldRelayout(_CenterWithOriginalSizeDelegate oldDelegate) {
    return oldDelegate != this;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CenterWithOriginalSizeDelegate &&
          runtimeType == other.runtimeType &&
          subjectSize == other.subjectSize &&
          basePosition == other.basePosition &&
          useImageScale == other.useImageScale;

  @override
  int get hashCode =>
      subjectSize.hashCode ^ basePosition.hashCode ^ useImageScale.hashCode;
}
