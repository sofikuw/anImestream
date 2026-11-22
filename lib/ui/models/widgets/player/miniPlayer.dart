import 'dart:async';

import 'package:flutter/material.dart';

import 'package:animestream/ui/models/providers/playerSession.dart';
import 'package:animestream/ui/pages/playerRoute.dart';

const double _initialWidth = 200;
const double _minWidth = 180;
const double _maxWidth = 360;
double _heightOf(double width) => width * 9 / 16;

/// Sits above the navigator: taps outside the window fall through to the app.
class MiniPlayerOverlay extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  const MiniPlayerOverlay({super.key, required this.navigatorKey});

  @override
  State<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends State<MiniPlayerOverlay> {
  final ValueNotifier<Offset> _drag = ValueNotifier(Offset.zero);
  final ValueNotifier<double> _width = ValueNotifier(_initialWidth);
  bool _dragging = false;
  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    PlayerSession.instance.addListener(_onSession);
  }

  @override
  void dispose() {
    PlayerSession.instance.removeListener(_onSession);
    _drag.dispose();
    _width.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!PlayerSession.instance.active) {
      _drag.value = Offset.zero;
      _width.value = _initialWidth;
    }
  }

  void _startDrag(_) {
    _dragStart = _drag.value;
    setState(() => _dragging = true);
  }

  void _updateDrag(Offset delta) => _drag.value += delta;

  /// Down closes; sideways hides the window and leaves an arrow; anything else
  /// settles against the nearest edge.
  void _endDrag(DragEndDetails details, Size size, double width, double height, double bottom) {
    final moved = _drag.value - (_dragStart ?? Offset.zero);
    _dragStart = null;
    setState(() => _dragging = false);

    if (moved.dy > 90 && moved.dy > moved.dx.abs()) {
      PlayerSession.instance.close();
      return;
    }
    if (moved.dx.abs() > 90 && moved.dx.abs() > moved.dy.abs()) {
      unawaited(PlayerSession.instance.collapse(toRight: moved.dx > 0));
      return;
    }

    final base = Offset(size.width - width - 12, size.height - height - bottom);
    const margin = 28.0;
    var x = (base.dx + _drag.value.dx).clamp(0.0, size.width - width);
    var y = (base.dy + _drag.value.dy).clamp(0.0, size.height - height);
    if (x < margin) x = 0;
    if (x + width > size.width - margin) x = size.width - width;
    if (y < margin) y = 0;
    if (y + height > size.height - margin) y = size.height - height;
    _drag.value = Offset(x - base.dx, y - base.dy);
  }

  /// The only thing left when the window is swiped aside. Swipe it back toward
  /// the middle (or tap it) to bring the player back.
  Widget _arrow(PlayerSession session, Size size, double bottom) {
    final onRight = session.collapseToRight;
    return Stack(
      children: [
        const IgnorePointer(child: SizedBox.expand()),
        Positioned(
          left: onRight ? null : 10,
          right: onRight ? 10 : null,
          top: (size.height - bottom) / 2 - 21,
          child: GestureDetector(
            onPanEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if ((onRight && velocity < -150) || (!onRight && velocity > 150)) {
                unawaited(session.uncollapse());
              }
            },
            onTap: () => unawaited(session.uncollapse()),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.black87,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white30),
              ),
              child: Icon(onRight ? Icons.chevron_left : Icons.chevron_right, color: Colors.white, size: 26),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: PlayerSession.instance,
        builder: (context, _) {
          final session = PlayerSession.instance;
          if (!session.mini || session.controller == null) {
            return const IgnorePointer(child: SizedBox.expand());
          }

          final size = MediaQuery.sizeOf(context);
          final bottom = MediaQuery.paddingOf(context).bottom + 72;
          if (session.collapsed) return _arrow(session, size, bottom);

          return ValueListenableBuilder<double>(
            valueListenable: _width,
            builder: (context, width, _) {
              final height = _heightOf(width);
              final base = Offset(size.width - width - 12, size.height - height - bottom);
              return ValueListenableBuilder<Offset>(
                valueListenable: _drag,
                child: MiniPlayerWindow(
                  key: ValueKey(session.routeId),
                  navigatorKey: widget.navigatorKey,
                  width: width,
                  onDragStart: _startDrag,
                  onDrag: _updateDrag,
                  onDragEnd: (details) => _endDrag(details, size, width, height, bottom),
                  onWidthChanged: (value) => _width.value = value.clamp(_minWidth, _maxWidth),
                ),
                builder: (context, delta, child) {
                  final x = (base.dx + delta.dx).clamp(0.0, size.width - width);
                  final y = (base.dy + delta.dy).clamp(0.0, size.height - height);
                  return Stack(
                    children: [
                      const IgnorePointer(child: SizedBox.expand()),
                      AnimatedPositioned(
                        left: x,
                        top: y,
                        duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child: child!,
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class MiniPlayerWindow extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final double width;
  final void Function(DragStartDetails details) onDragStart;
  final void Function(Offset delta) onDrag;
  final void Function(DragEndDetails details) onDragEnd;
  final void Function(double width) onWidthChanged;
  const MiniPlayerWindow({
    super.key,
    required this.navigatorKey,
    required this.width,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onWidthChanged,
  });

  @override
  State<MiniPlayerWindow> createState() => _MiniPlayerWindowState();
}

class _MiniPlayerWindowState extends State<MiniPlayerWindow> {
  bool _controlsVisible = false;
  double _widthAtPinch = _initialWidth;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    PlayerSession.instance.controller?.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _showControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    PlayerSession.instance.controller?.removeListener(_onTick);
    super.dispose();
  }

  /// First tap reveals the buttons, second tap on the video (not a button)
  /// returns to the full player.
  void _onVideoTap() {
    if (!_controlsVisible) {
      _showControls();
      return;
    }
    final session = PlayerSession.instance;
    final navigator = widget.navigatorKey.currentState ?? session.navigator;
    if (navigator == null) return;
    session.restore();
    openPlayerRoute(navigator);
  }

  @override
  Widget build(BuildContext context) {
    final session = PlayerSession.instance;
    final controller = session.controller;
    if (controller == null) return const SizedBox.shrink();

    final duration = controller.duration ?? 0;
    final progress = duration > 0 ? (controller.position ?? 0) / duration : 0.0;
    final playing = controller.isPlaying ?? false;

    Widget button(IconData icon, String tooltip, VoidCallback action) => IconButton(
          onPressed: () {
            _showControls();
            action();
          },
          icon: Icon(icon, color: Colors.white, size: 20),
          tooltip: tooltip,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        );

    return GestureDetector(
      onPanStart: (details) {
        _showControls();
        widget.onDragStart(details);
      },
      onPanUpdate: (details) => widget.onDrag(details.delta),
      onPanEnd: widget.onDragEnd,
      // Two fingers: resize, keeping the 16:9 shape.
      onScaleStart: (_) => _widthAtPinch = widget.width,
      onScaleUpdate: (details) => widget.onWidthChanged(_widthAtPinch * details.scale),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: widget.width,
            height: _heightOf(widget.width),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(onTap: _onVideoTap, child: controller.getMiniWidget()),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: Container(
                        height: 34,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xE6000000), Colors.transparent],
                          ),
                        ),
                        child: Row(
                          children: [
                            button(playing ? Icons.pause : Icons.play_arrow, playing ? 'Pause' : 'Play',
                                () => playing ? controller.pause() : controller.play()),
                            const Spacer(),
                            button(Icons.close, 'Close player', session.close),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 2.5,
                    backgroundColor: Colors.white30,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
