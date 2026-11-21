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
  Offset? _offset;

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
          final initial = Offset(size.width - _miniWidth - 12, size.height - _miniHeight - bottom);
          final offset = _offset ?? initial;
          final x = offset.dx.clamp(0.0, (size.width - _miniWidth).clamp(0.0, size.width));
          final y = offset.dy.clamp(0.0, (size.height - _miniHeight).clamp(0.0, size.height));

          return Stack(
            children: [
              const IgnorePointer(child: SizedBox.expand()),
              Positioned(
                left: x,
                top: y,
                child: GestureDetector(
                  onPanUpdate: (details) => setState(() => _offset = Offset(x, y) + details.delta),
                  child: MiniPlayerWindow(key: ValueKey(session.routeId), navigatorKey: widget.navigatorKey),
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
  const MiniPlayerWindow({super.key, required this.navigatorKey});

  @override
  State<MiniPlayerWindow> createState() => _MiniPlayerWindowState();
}

class _MiniPlayerWindowState extends State<MiniPlayerWindow> {
  @override
  void initState() {
    super.initState();
    // The watch page drops its listener on pop; the mini window keeps the
    // progress bar and play state live while the route is gone.
    PlayerSession.instance.controller?.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final session = PlayerSession.instance;
    final controller = session.controller;
    if (controller == null) return const SizedBox.shrink();

    final duration = controller.duration ?? 0;
    final progress = duration > 0 ? (controller.position ?? 0) / duration : 0.0;
    final playing = controller.isPlaying ?? false;

    return DecoratedBox(
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
              GestureDetector(onTap: _restore, child: controller.getMiniWidget()),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  onPressed: session.close,
                  icon: const Icon(Icons.close, color: Colors.white, size: 16),
                  tooltip: 'Close player',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                ),
              ),
              Positioned(
                left: 0,
                bottom: 3,
                child: IconButton(
                  onPressed: () async {
                    playing ? await controller.pause() : await controller.play();
                    _onTick();
                  },
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 20),
                  tooltip: playing ? 'Pause' : 'Play',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: Colors.white30,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
