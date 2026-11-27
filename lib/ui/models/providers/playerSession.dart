import 'package:flutter/material.dart';

import 'package:animestream/ui/models/playerControllers/videoController.dart';
import 'package:animestream/ui/models/providers/playerDataProvider.dart';
import 'package:animestream/ui/models/providers/playerProvider.dart';

/// The player lives above the navigator so it survives leaving the watch page.
///
/// One session at a time owns the platform controller and both providers. The
/// watch route borrows them; when that route is popped the session keeps them
/// alive and exposes the floating window instead.
class PlayerSession extends ChangeNotifier {
  PlayerSession._();
  static final PlayerSession instance = PlayerSession._();

  VideoController? _controller;
  PlayerDataProvider? _dataProvider;
  PlayerProvider? _playerProvider;
  NavigatorState? _navigator;
  bool _localSource = false;

  VideoController? get controller => _controller;
  PlayerDataProvider? get dataProvider => _dataProvider;
  PlayerProvider? get playerProvider => _playerProvider;
  NavigatorState? get navigator => _navigator;
  bool get localSource => _localSource;

  bool get active => _controller != null;

  bool _mini = false;
  bool get mini => _mini;

  /// Hidden to the side after a horizontal swipe, with only an arrow left to
  /// bring it back. Playback is paused while it is hidden.
  bool _collapsed = false;
  bool get collapsed => _collapsed;

  /// Transient full-screen video surface shown just before system PiP starts,
  /// so the platform captures the video instead of the mini overlay.
  bool _pipFullscreen = false;
  bool get pipFullscreen => _pipFullscreen;
  void setPipFullscreen(bool value) {
    if (_pipFullscreen == value) return;
    _pipFullscreen = value;
    notifyListeners();
  }

  /// Which edge the window was swiped off: left, right or bottom.
  String collapseEdge = 'right';

  bool _initialised = false;
  bool get initialised => _initialised;

  /// Identifies one visit to the watch route. A pop from an older visit must
  /// not minimise a newer playback session.
  int _routeId = 0;
  int get routeId => _routeId;

  void start({
    required VideoController controller,
    required PlayerDataProvider dataProvider,
    required PlayerProvider playerProvider,
    required NavigatorState navigator,
    bool localSource = false,
  }) {
    close();
    _controller = controller;
    _dataProvider = dataProvider;
    _playerProvider = playerProvider;
    _navigator = navigator;
    _localSource = localSource;
    _initialised = false;
    _mini = false;
    _collapsed = false;
    _pipFullscreen = false;
    notifyListeners();
  }

  /// Swipe aside: pause and leave a single arrow on that edge.
  Future<void> collapse({required String edge}) async {
    if (!active) return;
    _collapsed = true;
    collapseEdge = edge;
    await controller?.pause();
    notifyListeners();
  }

  /// Swipe the arrow back toward the middle to resume.
  Future<void> uncollapse() async {
    if (!_collapsed) return;
    _collapsed = false;
    await controller?.play();
    notifyListeners();
  }

  /// Called each time the watch route is pushed, including a restore from the
  /// mini window.
  int beginRoute() => ++_routeId;

  void markInitialised() {
    if (_initialised) return;
    _initialised = true;
    notifyListeners();
  }

  void minimise() {
    if (!active || _mini) return;
    _mini = true;
    notifyListeners();
  }

  void restore() {
    if (!active || !_mini) return;
    _mini = false;
    _collapsed = false;
    _pipFullscreen = false;
    notifyListeners();
  }

  /// The only place that tears down playback. Closing from the mini window
  /// ends the session; simply leaving the watch page does not.
  void close() {
    final controller = _controller;
    final dataProvider = _dataProvider;
    _controller = null;
    _dataProvider = null;
    _playerProvider = null;
    _navigator = null;
    _initialised = false;
    _mini = false;
    _collapsed = false;
    _pipFullscreen = false;
    _routeId++;
    notifyListeners();
    controller?.dispose();
    dataProvider?.stopRPC();
  }
}
