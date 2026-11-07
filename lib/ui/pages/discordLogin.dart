import 'dart:async';
import 'dart:convert';

import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/integrations/discord/gatewayRPC.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A real discord.com login, served in a WebView.
///
/// This is deliberately not OAuth: Discord's Gateway refuses OAuth access
/// tokens for presence, so the only credential that can drive Rich Presence is
/// the session token the website itself keeps in localStorage. The page logs in
/// normally, then hands that session to the app and removes it from the
/// WebView so it is not left signed in there.
class DiscordLoginPage extends StatefulWidget {
  const DiscordLoginPage({super.key});

  @override
  State<DiscordLoginPage> createState() => _DiscordLoginPageState();
}

class _DiscordLoginPageState extends State<DiscordLoginPage> {
  static const String _probe =
      "(() => { try { return localStorage.getItem('token') || '' } catch (e) { return '' } })()";

  late final WebViewController _controller;
  Timer? _poll;
  Timer? _timeout;
  bool _captured = false;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(appTheme.backgroundColor)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _probeToken(),
        ),
      )
      ..loadRequest(Uri.parse('https://discord.com/login'));

    _poll = Timer.periodic(const Duration(milliseconds: 900), (_) => _probeToken());
    _timeout = Timer(const Duration(minutes: 3), () {
      if (mounted && !_captured) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  Future<void> _probeToken() async {
    if (_captured) return;

    Object result;
    try {
      result = await _controller.runJavaScriptReturningResult(_probe);
    } catch (_) {
      return;
    }

    var raw = result.toString();
    if (raw.startsWith('"')) {
      try {
        raw = jsonDecode(raw) as String;
      } catch (_) {}
    }

    final token = DiscordTokenStore.normalize(raw);
    if (DiscordTokenStore.validationError(token) != null) return;

    _captured = true;
    _poll?.cancel();
    _timeout?.cancel();
    await DiscordTokenStore.save(token);

    try {
      await _controller.runJavaScript("try{localStorage.removeItem('token')}catch(e){}");
      await WebViewCookieManager().clearCookies();
      await _controller.clearCache();
    } catch (_) {}

    if (mounted) Navigator.of(context).pop('saved');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: appTheme.backgroundColor,
        foregroundColor: appTheme.textMainColor,
        title: const Text("Log in to Discord"),
      ),
      body: Column(
        children: [
          if (_slow)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: appTheme.backgroundSubColor,
              child: Text(
                "Taking a while? Discord sometimes blocks its login inside an app view. "
                "Use \"Paste instead\" if the page will not load.",
                style: TextStyle(color: appTheme.textSubColor, fontSize: 12),
              ),
            ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Signs in to discord.com and takes the session it stores. "
                      "Google/Apple sign-in does not work in this view; use email and password.",
                      style: TextStyle(color: appTheme.textSubColor, fontSize: 11),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop('manual'),
                    child: const Text("Paste instead"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
