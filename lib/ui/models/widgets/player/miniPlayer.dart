import 'dart:async';

import 'package:flutter/material.dart';

import 'package:animestream/ui/models/providers/playerSession.dart';
import 'package:animestream/ui/pages/playerRoute.dart';

const double _miniWidth = 200;
const double _miniHeight = 112.5;

/// Sits above the navigator: taps outside the window fall through to the app.
class MiniPlayerOverlay extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  const MiniPlayerOverlay({super.key, required this.navigatorKey});

  @override
  State<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends State<MiniPlayerOverlay> {
  /// Drag is a notifier so a pan only moves the window -- it never rebuilds the
  /// video widget or the whole overlay.
  final ValueNotifier<Offset> _drag = ValueNotifier(Offset.zero);

  @override
  void dispose() {
    _drag.dispose();
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
          final base = Offset(size.width - _miniWidth - 12, size.height - _miniHeight - bottom);

          return Stack(
            children: [
              const IgnorePointer(child: SizedBox.expand()),
              Positioned(
                left: base.dx,
                top: base.dy,
                child: ValueListenableBuilder<Offset>(
                  valueListenable: _drag,
                  child: MiniPlayerWindow(
                    key: ValueKey(session.routeId),
                    navigatorKey: widget.navigatorKey,
                    onDrag: (delta) => _drag.value += delta,
                  ),
                  builder: (context, delta, child) {
                    final x = (base.dx + delta.dx).clamp(0.0, size.width - _miniWidth);
                    final y = (base.dy + delta.dy).clamp(0.0, size.height - _miniHeight);
                    return Transform.translate(
                      offset: Offset(x - base.dx, y - base.dy),
                      child: child,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MiniPlayerWindow extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final void Function(Offset delta) onDrag;
  const MiniPlayerWindow({
    super.key,
    required this.navigatorKey,
    required this.onDrag,
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

  void _onVideoTap() {
    // First tap reveals the controls; a second one expands the player.
    _controlsVisible ? _restore() : _showControls();
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
            width: _miniWidth,
            height: _miniHeight,
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
                            colors: [Colors.black, Colors.transparent],
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => _act(() => player!.fastForward(-10)),
                              icon: const Icon(Icons.replay_10, color: Colors.white, size: 18),
                              tooltip: 'Back 10 seconds',
                              padding: const EdgeInsets.all(2),
                              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                            ),
                            IconButton(
                              onPressed: () => _act(() => playing ? controller.pause() : controller.play()),
                              icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 20),
                              tooltip: playing ? 'Pause' : 'Play',
                              padding: const EdgeInsets.all(2),
                              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                            ),
                            if (hasNext)
                              IconButton(
                                onPressed: () => _act(() async => player!.playPreloadedEpisode(data!)),
                                icon: const Icon(Icons.skip_next, color: Colors.white, size: 18),
                                tooltip: 'Next episode',
                                padding: const EdgeInsets.all(2),
                                constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                              ),
                            const Spacer(),
                            IconButton(
                              onPressed: _restore,
                              icon: const Icon(Icons.open_in_full, color: Colors.white, size: 17),
                              tooltip: 'Back to full player',
                              padding: const EdgeInsets.all(2),
                              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                            ),
                            IconButton(
                              onPressed: session.close,
                              icon: const Icon(Icons.close, color: Colors.white, size: 18),
                              tooltip: 'Close player',
                              padding: const EdgeInsets.all(2),
                              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                            ),
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
