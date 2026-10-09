import 'dart:io';

import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class GestureOverlay extends StatefulWidget {
  final Widget child;
  // Feature Flags
  final bool isDesktop;
  final bool controlsLocked;
  final bool enableHoldToSpeedUp;

  // Hover callback
  final void Function(PointerHoverEvent) onPointerHover;

  // Speed Control Callbacks (Long Press + Horizontal Drag)
  final VoidCallback onSpeedUpStart;
  final void Function(bool increase) onSpeedChange;
  final VoidCallback onSpeedUpEnd;

  // Volume & Brightness Callbacks (Vertical Drag)
  final Future<double> Function() getInitialVolume;
  final Future<double> Function() getInitialBrightness;
  final void Function(double) onVolumeUpdate;
  final void Function(double) onBrightnessUpdate;
  final VoidCallback onVerticalDragEnd;

  const GestureOverlay({
    super.key,
    required this.child,
    required this.isDesktop,
    required this.controlsLocked,
    required this.enableHoldToSpeedUp,
    required this.onPointerHover,
    required this.onSpeedUpStart,
    required this.onSpeedChange,
    required this.onSpeedUpEnd,
    required this.getInitialVolume,
    required this.getInitialBrightness,
    required this.onVolumeUpdate,
    required this.onBrightnessUpdate,
    required this.onVerticalDragEnd,
  });

  @override
  State<GestureOverlay> createState() => _GestureOverlayState();
}

class _GestureOverlayState extends State<GestureOverlay> {
  bool _isSpeedingUp = false;

  double? _lastSpeedChangeOffset;

  // Vertical Drag (Volume/Brightness) State
  double? _dragStartY;

  double? _startValue;

  bool _isLeftHalfDrag = false;

  final double _verticalDragSensitivity = 300.0;

  bool get _playerGesturesEnabled => currentUserSettings?.enablePlayerGestures ?? false;

  bool get _holdToSpeedUpEnabled =>
      currentUserSettings?.enableHoldToSpeedUp ?? widget.enableHoldToSpeedUp;

  final isDesktop = Platform.isWindows || Platform.isLinux;

  // --- VERTICAL DRAG (Volume / Brightness) ---
  void _onVerticalDragStart(DragStartDetails details) async {
    if (widget.controlsLocked || !_playerGesturesEnabled) return;
    
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;

    // the middle part of screen is free from gestures.
    final freeSpace = screenWidth / 3;
    
    // Add dead zones at top and bottom to prevent accidental triggers (like status bar pulldown)
    final verticalSafeArea = (screenHeight * 0.1).clamp(40.0, 80.0);
    if (details.localPosition.dy < verticalSafeArea || 
        details.localPosition.dy > screenHeight - verticalSafeArea) {
      return;
    }

    final isAtFreeSpace = details.localPosition.dx > freeSpace && details.localPosition.dx < (screenWidth - freeSpace);
    
    // Add dead zones at left and right edges to prevent interference with system 'back' gestures
    final horizontalSafeArea = 40.0;
    if (details.localPosition.dx < horizontalSafeArea ||
        details.localPosition.dx > screenWidth - horizontalSafeArea || isAtFreeSpace) {
      return;
    }

    _dragStartY = details.localPosition.dy;
    _isLeftHalfDrag = details.localPosition.dx < (screenWidth / 2);

    if (_isLeftHalfDrag) {
      _startValue = await widget.getInitialBrightness();
    } else {
      _startValue = await widget.getInitialVolume();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (widget.controlsLocked || !_playerGesturesEnabled || _dragStartY == null || _startValue == null) return;

    final double dragDistance = _dragStartY! - details.localPosition.dy;
    final double changePercentage = dragDistance / _verticalDragSensitivity;
    final double newValue = (_startValue! + changePercentage).clamp(0.0, 1.0);

    if (_isLeftHalfDrag) {
      widget.onBrightnessUpdate(newValue);
    } else {
      widget.onVolumeUpdate(newValue);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _dragStartY = null;
    _startValue = null;
    widget.onVerticalDragEnd();
  }

  // Speed Control
  void _onLongPressStart(LongPressStartDetails details) {
    if (widget.isDesktop || widget.controlsLocked || !_holdToSpeedUpEnabled) return;
    
    _isSpeedingUp = true;
    _lastSpeedChangeOffset = null;
    widget.onSpeedUpStart();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (widget.isDesktop || !_isSpeedingUp) return;

    final offset = details.localOffsetFromOrigin.dx;
    if (_lastSpeedChangeOffset == null) {
      _lastSpeedChangeOffset = offset;
      return;
    }

    final delta = (offset - _lastSpeedChangeOffset!).abs();
    if (delta >= 40) { // 40px threshold to snap to next speed
      widget.onSpeedChange(offset > _lastSpeedChangeOffset!);
      _lastSpeedChangeOffset = offset;
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_isSpeedingUp || widget.isDesktop) return;
    _isSpeedingUp = false;
    _lastSpeedChangeOffset = null;
    widget.onSpeedUpEnd();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: widget.onPointerHover,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: isDesktop ? null : _onVerticalDragStart,
        onVerticalDragUpdate: isDesktop ? null : _onVerticalDragUpdate,
        onVerticalDragEnd: isDesktop ? null : _onVerticalDragEnd,
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMoveUpdate,
        onLongPressEnd: _onLongPressEnd,
        child: widget.child,
      ),
    );
  }
}
