import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:animestream/ui/models/providers/playerSession.dart';
import 'package:animestream/ui/pages/watch.dart';

/// Push the watch page bound to the live session, so leaving it minimises the
/// video instead of destroying it.
Future<void> openPlayerRoute(NavigatorState navigator) async {
  final session = PlayerSession.instance;
  if (!session.active) return;

  final routeId = session.beginRoute();
  session.playerProvider?.setAutoPip(true);
  await navigator.push(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: session.dataProvider!),
          ChangeNotifierProvider.value(value: session.playerProvider!),
        ],
        child: Watch(controller: session.controller!, localSource: session.localSource),
      ),
    ),
  );

  if (session.active && session.routeId == routeId) {
    // Keep auto-PiP armed: leaving the app while the mini window is showing
    // should still open the system PiP window.
    session.playerProvider?.setAutoPip(true);
    session.minimise();
  }
}
