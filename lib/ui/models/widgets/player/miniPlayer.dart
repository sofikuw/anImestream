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
  /// Drag and resize are notifiers so a pan only moves the window -- it never
  /// rebuilds the video widget or the whole overlay.
  final ValueNotifier<Offset> _drag = ValueNotifier(Offset.zero);
  final ValueNotifier<double> _width = ValueNotifier(_initialWidth);

  @override
  void dispose() {
    _drag.dispose();
    _width.dispose();
    super.dispose();
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
                  onDrag: (delta) => _drag.value += delta,
                  onResize: (delta) => _width.value = (_width.value + delta).clamp(_minWidth, _maxWidth),
                ),
                builder: (context, delta, child) {
                  final x = (base.dx + delta.dx).clamp(0.0, size.width - width);
                  final y = (base.dy + delta.dy).clamp(0.0, size.height - height);
                  return Stack(
                    children: [
                      const IgnorePointer(child: SizedBox.expand()),
                      Positioned(left: x, top: y, child: child!),
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
  final void Function(Offset delta) onDrag;
  final void Function(double delta) onResize;
  const MiniPlayerWindow({
    super.key,
    required this.navigatorKey,
    required this.width,
    required this.onDrag,
    required this.onResize,
  });

  @override
  State<MiniPlayerWindow> createState() => _MiniPlayerWindowState();
}

class _MiniPlayerWindowState extends State<MiniPlayerWindow> {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    PlayerSession.instance.controller?.addListener(_onTick);
    _showControls();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  /// Controls fade out a few seconds after the last interaction, like the
  /// YouTube mini player.
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

  void _restore() {
    final session = PlayerSession.instance;
    final navigator = session.navigator ?? widget.navigatorKey.currentState;
    if (navigator == null) return;
    session.restore();
    openPlayerRoute(navigator);
  }

  void _act(Future<void> Function() action) {
    _showControls();
    unawaited(action());
  }

  @override
  Widget build(BuildContext context) {
    final session = PlayerSession.instance;
    final controller = session.controller;
    if (controller == null) return const SizedBox.shrink();

    final duration = controller.duration ?? 0;
    final progress = duration > 0 ? (controller.position ?? 0) / duration : 0.0;
    final playing = controller.isPlaying ?? false;
    final data = session.dataProvider;
    final player = session.playerProvider;
    final hasNext = data != null &&
        player != null &&
        data.state.currentEpIndex + 1 < data.epLinks.length &&
        data.state.preloadedSources.isNotEmpty;

    Widget button(IconData icon, String tooltip, VoidCallback? onPressed) => IconButton(
          onPressed: onPressed == null ? null : () => _act(() async { onPressed(); }),
          icon: Icon(icon, color: Colors.white, size: 18),
          tooltip: tooltip,
          padding: const EdgeInsets.all(1),
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        );

    return GestureDetector(
      onPanStart: (_) => _showControls(),
      onPanUpdate: (details) => widget.onDrag(details.delta),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: widget.width,
            height: _heightOf(widget.width),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Tapping the video reveals the controls; only the expand
                // button returns to the full player.
                GestureDetector(onTap: _showControls, child: controller.getMiniWidget()),
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
                        height: 32,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black, Colors.transparent],
                          ),
                        ),
                        child: Row(
                          children: [
                            button(Icons.replay_10, 'Back 10 seconds', () => player!.fastForward(-10)),
                            button(playing ? Icons.pause : Icons.play_arrow,
                                playing ? 'Pause' : 'Play', () => playing ? controller.pause() : controller.play()),
                            button(Icons.forward_10, 'Forward 10 seconds', () => player!.fastForward(10)),
                            if (hasNext)
                              button(Icons.skip_next, 'Next episode', () => player!.playPreloadedEpisode(data!)),
                            const Spacer(),
                            button(Icons.open_in_full, 'Back to full player', _restore),
                            button(Icons.close, 'Close player', session.close),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: GestureDetector(
                    onPanStart: (_) => _showControls(),
                    onPanUpdate: (details) => widget.onResize(details.delta.dx),
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: Center(child: Icon(Icons.aspect_ratio, color: Colors.white70, size: 13)),
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
