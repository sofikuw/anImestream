import 'dart:io';

import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/app/ios_pip_service.dart';
import 'package:animestream/ui/models/playerControllers/videoController.dart';
import 'package:animestream/ui/models/providers/playerProvider.dart';
import 'package:animestream/ui/models/widgets/player/controls.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Main in-app watch screen used by the existing server/download navigation.
class Watch extends StatefulWidget {
  final VideoController controller;
  final bool localSource;

  const Watch({
    super.key,
    required this.controller,
    this.localSource = false,
  });

  @override
  State<Watch> createState() => _WatchState();
}

class _WatchState extends State<Watch> with WidgetsBindingObserver {
  bool _autoPipRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      _autoPipRequested = false;
      return;
    }

    if (!Platform.isIOS ||
        state != AppLifecycleState.inactive ||
        _autoPipRequested ||
        currentUserSettings?.enablePipOnMinimize != true ||
        IosPipService().isPipActive) {
      return;
    }

    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);
    if (playerProvider.controller.isPlaying != true) return;

    _autoPipRequested = true;
    try {
      await playerProvider.setPip(true);
    } catch (error) {
      _autoPipRequested = false;
      debugPrint('Automatic iOS PiP failed: $error');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: widget.controller.getWidget()),
            const Controls(),
          ],
        ),
      ),
    );
  }
}

/// Optional simple standalone page for callers that only have a direct URL.
/// The normal app flow should use [Watch] above so it retains the existing
/// Provider/player architecture.
class WatchPage extends StatelessWidget {
  final String animeTitle;
  final String episodeNumber;
  final String videoUrl;

  const WatchPage({
    super.key,
    required this.animeTitle,
    required this.episodeNumber,
    required this.videoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$animeTitle - Ep $episodeNumber')),
      body: const Center(
        child: Text('Use the normal Watch route for playback.'),
      ),
    );
  }
}
