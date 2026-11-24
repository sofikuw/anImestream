import 'dart:async';

import 'package:flutter/material.dart';

import 'package:animestream/ui/models/providers/playerSession.dart';
import 'package:animestream/ui/pages/playerRoute.dart';

const double _initialWidth = 260;
const double _minWidth = 200;
const double _maxWidth = 480;
double _heightOf(double width) => width * 9 / 16;

double maxWidthFor(double screenWidth) {
  final available = screenWidth - 24;
  if (available < _minWidth) return _minWidth;
  return _maxWidth < available ? _maxWidth : available;
}

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
  Offset? _hiddenPosition;

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
      _hiddenPosition = null;
    }
  }

  void _startDrag(_) => setState(() => _dragging = true);

  void _updateDrag(Offset delta) => _drag.value += delta;

  Offset _base(Size size, double width, double height, double bottom) =>
      Offset(size.width - width - 12, size.height - height - bottom);

  /// YouTube-style: horizontal position snaps to the nearest side, vertical
  /// position stays wherever the user left it (clamped to the screen).
  Offset _snapped(Size size, double width, double height, double bottom) {
    final base = _base(size, width, height, bottom);
    final maxY = size.height - height - bottom;
    final x = (base.dx + _drag.value.dx).clamp(0.0, size.width - width);
    final y = (base.dy + _drag.value.dy).clamp(0.0, maxY < 0 ? 0.0 : maxY);
    return Offset(x < (size.width - width) / 2 ? 0.0 : size.width - width, y);
  }

  Offset _offscreen(String edge, Offset home, Size size, double width) {
    switch (edge) {
      case 'left':
        return Offset(-width - 12, home.dy);
      case 'bottom':
        return Offset(home.dx, size.height + 12);
      default:
        return Offset(size.width + 12, home.dy);
    }
  }

  /// Flick off any edge: the window animates away, pauses, and leaves an arrow
  /// at the edge it disappeared through.
  void _endDrag(DragEndDetails details, Size size, double width, double height, double bottom) {
    setState(() => _dragging = false);

    final session = PlayerSession.instance;
    String? edge;
    // Hide only once more than half the window is actually off-screen.
    final current = Offset(
      _base(size, width, height, bottom).dx + _drag.value.dx,
      _base(size, width, height, bottom).dy + _drag.value.dy,
    );
    if (current.dx > size.width - width / 2) edge = 'right';
    if (current.dx < -width / 2) edge = 'left';

    if (edge != null) {
      final home = _snapped(size, width, height, bottom);
      _hiddenPosition = home;
      _drag.value = _offscreen(edge, home, size, width) - _base(size, width, height, bottom);
      unawaited(session.collapse(edge: edge));
      return;
    }

    _drag.value = _snapped(size, width, height, bottom) - _base(size, width, height, bottom);
  }

  void _restoreFromArrow(PlayerSession session, Size size, double width, double height, double bottom) {
    final home = _hiddenPosition ?? _snapped(size, width, height, bottom);
    _drag.value = home - _base(size, width, height, bottom);
    unawaited(session.uncollapse());
  }

  Widget _arrow(PlayerSession session, Size size, double bottom) {
    final edge = session.collapseEdge;
    final icon = edge == 'right'
        ? Icons.chevron_left
        : edge == 'left'
            ? Icons.chevron_right
            : Icons.keyboard_arrow_up;

    return AnimatedOpacity(
      opacity: session.collapsed ? 0.4 : 0,
      duration: const Duration(milliseconds: 220),
      child: IgnorePointer(
        ignoring: !session.collapsed,
        child: GestureDetector(
          onTap: () => _restoreFromArrow(session, size, _width.value, _heightOf(_width.value), bottom),
          onPanEnd: (details) {
            final velocity = details.velocity.pixelsPerSecond;
            final towardCenter = edge == 'right'
                ? velocity.dx < -100
                : edge == 'left'
                    ? velocity.dx > 100
                    : velocity.dy < -100;
            if (towardCenter) {
              _restoreFromArrow(session, size, _width.value, _heightOf(_width.value), bottom);
            }
          },
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.black87,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white30),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
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
          final bottom = MediaQuery.paddingOf(context).bottom + 8;

          // Keep the window inside the screen even on small displays.
          final maxWidth = maxWidthFor(size.width);

          return ValueListenableBuilder<double>(
            valueListenable: _width,
            builder: (context, storedWidth, _) {
              final width = storedWidth.clamp(_minWidth, maxWidth);
              final height = _heightOf(width);
              final base = _base(size, width, height, bottom);
              return ValueListenableBuilder<Offset>(
                valueListenable: _drag,
                child: MiniPlayerWindow(
                  key: ValueKey(session.routeId),
                  navigatorKey: widget.navigatorKey,
                  width: width,
                  onDragStart: _startDrag,
                  onDrag: _updateDrag,
                  onDragEnd: (details) => _endDrag(details, size, width, height, bottom),
                  onWidthChanged: (value) => _width.value = value.clamp(_minWidth, maxWidth),
                ),
                builder: (context, delta, child) {
                  final hidden = session.collapsed
                      ? _offscreen(session.collapseEdge, _hiddenPosition ?? base, size, width)
                      : Offset(base.dx + delta.dx, base.dy + delta.dy);
                  return Stack(
                    children: [
                      const IgnorePointer(child: SizedBox.expand()),
                      AnimatedPositioned(
                        left: hidden.dx,
                        top: hidden.dy,
                        duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        child: child!,
                      ),
                      Positioned(
                        left: leftOfArrow(session, size),
                        right: rightOfArrow(session, size),
                        top: (_hiddenPosition?.dy ?? (size.height - bottom) / 2) + height / 2 - 14,
                        child: _arrow(session, size, bottom),
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

  // Positioning helpers kept out of the builder to avoid duplicate math.
  double? leftOfArrow(PlayerSession session, Size size) => session.collapseEdge == 'left'
      ? 10
      : session.collapseEdge == 'bottom'
          ? (size.width - 28) / 2
          : null;
  double? rightOfArrow(PlayerSession session, Size size) => session.collapseEdge == 'right' ? 10 : null;
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
  Timer? _hideTimer;
  final Map<int, Offset> _pointers = {};
  double? _pinchStartWidth;
  double? _pinchStartDistance;

  bool get _pinching => _pointers.length >= 2;

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

  void _pointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      final points = _pointers.values.toList();
      _pinchStartDistance = (points[0] - points[1]).distance;
      _pinchStartWidth = widget.width;
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    if (!_pinching || _pinchStartDistance == null || _pinchStartDistance == 0) return;
    final points = _pointers.values.take(2).toList();
    final distance = (points[0] - points[1]).distance;
    widget.onWidthChanged(_pinchStartWidth! * distance / _pinchStartDistance!);
  }

  void _pointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) {
      _pinchStartDistance = null;
      _pinchStartWidth = null;
    }
  }

  /// First tap shows the two buttons; second tap on the video expands.
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

    return Listener(
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        if (_pointers.length < 2) {
          _pinchStartDistance = null;
          _pinchStartWidth = null;
        }
      },
      child: GestureDetector(
        onPanStart: (details) {
          if (_pinching) return;
          _showControls();
          widget.onDragStart(details);
        },
        onPanUpdate: (details) {
          if (_pinching) return;
          widget.onDrag(details.delta);
        },
        onPanEnd: (details) {
          if (_pinching) return;
          widget.onDragEnd(details);
        },
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
      ),
    );
  }
}
