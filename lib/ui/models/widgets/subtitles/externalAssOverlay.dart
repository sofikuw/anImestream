import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:animestream/core/commons/enums.dart';
import 'package:animestream/ui/models/playerControllers/videoController.dart';
import 'package:animestream/ui/models/widgets/subtitles/subViewer.dart';
import 'package:animestream/ui/models/widgets/subtitles/subtitleSettings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Optional libass overlay for external ASS/SSA files.
///
/// Uses the Android method channel instead of Better Player's subtitle pipeline.
/// Falls back to the regular [SubViewer] when the native renderer is missing
/// (for example on x86_64 builds, where the assrender AAR has no native libs).
class ExternalAssOverlay extends StatefulWidget {
  const ExternalAssOverlay({
    super.key,
    required this.controller,
    required this.subtitleSource,
    required this.settings,
    this.headers = const {},
    this.isOffline = false,
  });

  final VideoController controller;
  final String subtitleSource;
  final SubtitleSettings settings;
  final Map<String, String> headers;
  final bool isOffline;

  @override
  State<ExternalAssOverlay> createState() => _ExternalAssOverlayState();
}

class _ExternalAssOverlayState extends State<ExternalAssOverlay> {
  static const _channel = MethodChannel('animestream.app/assrender');
  Timer? _timer;
  Uint8List? _frame;
  bool _ready = false;
  bool _fallback = false;
  bool _rendering = false;
  int _generation = 0;
  int _lastPosition = -1;
  int _loadedGeneration = -1;

  int _basePosition = 0;
  final Stopwatch _sincePoll = Stopwatch();

  int get _position {
    final polled = widget.controller.position ?? 0;
    if (polled != _basePosition) {
      _basePosition = polled;
      _sincePoll
        ..reset()
        ..start();
      return polled;
    }
    if (widget.controller.isPlaying == true) {
      return _basePosition + _sincePoll.elapsedMilliseconds;
    }
    return _basePosition;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ExternalAssOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subtitleSource != widget.subtitleSource ||
        oldWidget.isOffline != widget.isOffline ||
        oldWidget.headers.toString() != widget.headers.toString()) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _timer?.cancel();
    _ready = false;
    _fallback = false;
    _frame = null;
    _lastPosition = -1;
    if (!Platform.isAndroid) {
      _fallback = true;
      return;
    }

    try {
      final supported = await _channel.invokeMethod<bool>('supported') ?? false;
      if (!mounted || generation != _generation) return;
      if (!supported) {
        setState(() => _fallback = true);
        return;
      }

      final Uint8List bytes;
      if (widget.isOffline) {
        bytes = await File(widget.subtitleSource).readAsBytes();
      } else {
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse(widget.subtitleSource));
          widget.headers.forEach(request.headers.set);
          final response = await request.close();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw HttpException('ASS HTTP ${response.statusCode}');
          }
          final chunks = await response.fold<List<int>>(
            <int>[], (out, chunk) => out..addAll(chunk),
          );
          bytes = Uint8List.fromList(chunks);
        } finally {
          client.close(force: true);
        }
      }
      if (!mounted || generation != _generation) return;
      debugPrint('[ASSRENDER] Loading ${bytes.length} bytes from ${widget.subtitleSource}');
      final loaded = await _channel.invokeMethod<bool>('load', {
        'script': bytes,
        'width': 1280,
        'height': 720,
      });
      if (!mounted || generation != _generation) return;
      if (loaded != true) {
        setState(() => _fallback = true);
        return;
      }
      _loadedGeneration = generation;
      _ready = true;
      debugPrint('[ASSRENDER] Script loaded successfully');
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _render());
      _render();
    } catch (error) {
      debugPrint('[ASSRENDER] Native overlay unavailable: $error');
      if (mounted && generation == _generation) {
        setState(() => _fallback = true);
      }
    }
  }

  Future<void> _render() async {
    if (!_ready || _rendering || !mounted) return;
    final generation = _loadedGeneration;
    final position = _position;
    if (position == _lastPosition) return;
    _rendering = true;
    try {
      final frame = await _channel.invokeMethod<Uint8List>(
        'render', {'timeMs': position},
      );
      if (!mounted || !_ready || generation != _generation) return;
      _lastPosition = position;
      setState(() => _frame = frame);
    } catch (error) {
      debugPrint('[ASSRENDER] Render failed: $error');
      _ready = false;
      _timer?.cancel();
      if (mounted) {
        setState(() => _fallback = true);
      }
    } finally {
      _rendering = false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    _sincePoll.stop();
    if (_ready) {
      _channel.invokeMethod<void>('dispose').catchError((Object _) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fallback) {
      return SubViewer(
        controller: widget.controller,
        format: SubtitleFormat.ASS,
        subtitleSource: widget.subtitleSource,
        settings: widget.settings,
        headers: widget.headers,
        isOffline: widget.isOffline,
      );
    }

    final frame = _frame;
    return IgnorePointer(
      child: frame == null
          ? const SizedBox.expand()
          : SizedBox.expand(
              child: Image.memory(
                frame,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
              ),
            ),
    );
  }
}
