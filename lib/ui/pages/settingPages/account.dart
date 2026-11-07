import 'dart:io';

import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums.dart';
import 'package:animestream/core/data/secureStorage.dart';
import 'package:animestream/core/data/settings.dart';
import 'package:animestream/core/data/types.dart';
import 'package:animestream/core/database/anilist/anilist.dart';
import 'package:animestream/core/database/anilist/login.dart';
import 'package:animestream/core/database/anilist/types.dart';
import 'package:animestream/core/database/database.dart';
import 'package:animestream/core/database/mal/login.dart';
import 'package:animestream/core/database/simkl/login.dart';
import 'package:animestream/core/database/simkl/types.dart';
import 'package:animestream/core/integrations/discord/gatewayRPC.dart';
import 'package:animestream/ui/models/snackBar.dart';
import 'package:animestream/ui/models/widgets/loader.dart';
import 'package:animestream/ui/pages/discordLogin.dart';
import 'package:animestream/ui/pages/settingPages/common.dart';
import 'package:animestream/ui/models/providers/appProvider.dart';
import 'package:animestream/ui/pages/settingPages/widgets/database_account_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccountSetting extends StatefulWidget {
  const AccountSetting({super.key});

  @override
  State<AccountSetting> createState() => _AccountSettingState();
}

class _AccountSettingState extends State<AccountSetting> {
  bool anilistLoggedIn = false;
  bool simklLoggedIn = false;
  bool malLoggedIn = false;
  bool discordLoggedIn = false;
  bool hasDiscordToken = false;
  String? discordUsername;

  UserModal? user;
  UserModal? simklUser;
  UserModal? malUser;

  bool loading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _checkLogins();
    if (!anilistLoggedIn && !simklLoggedIn && !malLoggedIn && !discordLoggedIn) {
      if (mounted) {
        setState(() => loading = false);
      }
      return;
    }

    await Future.wait([
      if (anilistLoggedIn) _fetchAnilistProfile(),
      if (simklLoggedIn) _fetchSimklProfile(),
      if (malLoggedIn) _fetchMalProfile(),
    ]);

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> _checkLogins() async {
    final aniToken = await getSecureVal(SecureStorageKey.anilistToken);
    final simklToken = await getSecureVal(SecureStorageKey.simklToken);
    final malToken = await getSecureVal(SecureStorageKey.malToken);
    final discordToken = await getSecureVal(SecureStorageKey.discordToken);
    var discordName = await getSecureVal(SecureStorageKey.discordUsername);
    if (discordToken != null && (discordName == null || discordName.isEmpty)) {
      discordName = await DiscordTokenStore.fetchUsername();
      if (discordName != null) {
        await storeSecureVal(SecureStorageKey.discordUsername, discordName);
      }
    }

    final mobile = Platform.isAndroid || Platform.isIOS;

    if (mounted) {
      setState(() {
        anilistLoggedIn = aniToken != null;
        simklLoggedIn = simklToken != null;
        malLoggedIn = malToken != null;
        discordLoggedIn =
            discordToken != null || (!mobile && (currentUserSettings?.enableDiscordRichPresence ?? false));
        hasDiscordToken = discordToken != null;
        discordUsername = discordName;
      });
    }
  }

  Future<void> _fetchAnilistProfile() async {
    try {
      final res = await AniListLogin().getUserProfile();
      if (mounted) setState(() => user = res);
    } catch (err) {
      if (err is AnilistApiException) {
        if (err.statusCode == 401 || err.message.toLowerCase().contains("invalid token")) {
          floatingSnackBar("Anilist token is invalid. Login again!");
          await AniListLogin().removeToken();
          if (mounted) setState(() => anilistLoggedIn = false);
        }
      } else {
        floatingSnackBar("Anilist error: ${err.toString()}");
        if (mounted) setState(() => anilistLoggedIn = false);
      }
    }
  }

  Future<void> _fetchSimklProfile() async {
    try {
      final res = await SimklLogin().getUserProfile();
      if (mounted) setState(() => simklUser = res);
    } on SimklException catch (err) {
      if (err.isUnauthorized) {
        floatingSnackBar("Simkl token is invalid. Login again!");
        await SimklLogin().removeToken();
      }
      if (mounted) setState(() => simklLoggedIn = false);
    } catch (err) {
      if (mounted) setState(() => simklLoggedIn = false);
    }
  }

  Future<void> _fetchMalProfile() async {
    try {
      final res = await MALLogin().getUserProfile();
      if (mounted) setState(() => malUser = res);
    } catch (err) {
      floatingSnackBar("MAL error: ${err.toString()}");
      if (mounted) setState(() => malLoggedIn = false);
    }
  }

  void _handleLogout(Databases db) async {
    switch (db) {
      case Databases.anilist:
        await AniListLogin().removeToken();
        if (mounted) setState(() => anilistLoggedIn = false);
        break;
      case Databases.simkl:
        await SimklLogin().removeToken();
        if (mounted) setState(() => simklLoggedIn = false);
        break;
      case Databases.mal:
        await MALLogin().removeToken();
        if (mounted) setState(() => malLoggedIn = false);
        break;
    }
    floatingSnackBar("Logged out successfully!");
  }

  void _handleLogin(Databases db) async {
    bool logged = false;
    try {
      switch (db) {
        case Databases.anilist:
          logged = await AniListLogin().initiateLogin();
          break;
        case Databases.simkl:
          logged = await SimklLogin().initiateLogin();
          break;
        case Databases.mal:
          logged = await MALLogin().initiateLogin();
          break;
      }

      if (logged) {
        floatingSnackBar("Login successful!");
        if (mounted) {
          Provider.of<AppProvider>(context, listen: false).justRefresh();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AccountSetting()),
          );
        }
      }
    } catch (err) {
      floatingSnackBar("Login failed! Try again");
      print(err.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      body: SingleChildScrollView(
        child: Padding(
          padding: pagePadding(context),
          child: Column(
            // crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              settingPagesTitleHeader(context, "Account"),
              loading
                  ? Container(
                      padding: const EdgeInsets.only(top: 30),
                      child: Center(
                        child: AnimeStreamLoading(
                          color: appTheme.accentColor,
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      // runAlignment: WrapAlignment.center,
                      // alignment: WrapAlignment.center,
                      // crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ...Databases.values.map((db) {
                          bool isLoggedIn = false;
                          UserModal? userModal;

                          switch (db) {
                            case Databases.anilist:
                              isLoggedIn = anilistLoggedIn;
                              userModal = user;
                              break;
                            case Databases.simkl:
                              isLoggedIn = simklLoggedIn;
                              userModal = simklUser;
                              break;
                            case Databases.mal:
                              isLoggedIn = malLoggedIn;
                              userModal = malUser;
                              break;
                          }

                          return DatabaseAccountCard(
                            databaseName: db.name,
                            loggedIn: isLoggedIn,
                            userModal: userModal,
                            onLogin: () => _handleLogin(db),
                            onLogout: () => _handleLogout(db),
                          );
                        }).toList(),
                        DatabaseAccountCard(
                          databaseName: "discord",
                          loggedIn: discordLoggedIn,
                          userModal: discordLoggedIn
                              ? UserModal(
                                  id: -1,
                                  name: discordUsername ?? "Discord user",
                                  avatar: null,
                                  banner: null,
                                )
                              : null,
                          onLogin: _discordLogin,
                          onLogout: _discordLogout,
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> writeSettings(SettingsModal settings) async {
    await Settings().writeSettings(settings);
    if (mounted) setState(() {});
  }

  Future<void> _discordLogin() async {
    final mobile = Platform.isAndroid || Platform.isIOS;
    if (mobile && !hasDiscordToken) {
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const DiscordLoginPage()),
      );
      if (!mounted) return;
      if (result == 'manual') {
        final saved = await _promptDiscordToken(context);
        if (!saved) return;
      } else if (result != 'saved') {
        return;
      }
      if (!mounted) return;
    }
    if (mobile) {
      final accepted = await _confirmDiscordRisk(context);
      if (!accepted) return;
    }

    await writeSettings(SettingsModal(enableDiscordRichPresence: true));
    if (!mounted) return;
    setState(() {});

    // Verify the token right away so a bad one fails here instead of silently
    // during playback. The socket connects before IDENTIFY completes, so wait
    // briefly for READY or for Discord to reject the token.
    final presence = DiscordPresenceManager.instance;
    await presence.start();
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (!presence.isConnected &&
        presence.lastError.value == null &&
        DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final problem = presence.lastError.value ??
        (presence.isConnected ? null : 'Discord did not respond. Check your connection.');
    if (problem != null) {
      await presence.stop();
      await writeSettings(SettingsModal(enableDiscordRichPresence: false));
      if (!mounted) return;
      setState(() {});
      floatingSnackBar(problem);
      return;
    }

    final tokenPresent = await DiscordTokenStore.hasToken();
    final storedName = await getSecureVal(SecureStorageKey.discordUsername);
    final username = presence.username ?? storedName ?? await DiscordTokenStore.fetchUsername();
    if (username != null) {
      await storeSecureVal(SecureStorageKey.discordUsername, username);
    }
    if (!mounted) return;
    setState(() {
      discordLoggedIn = true;
      hasDiscordToken = tokenPresent;
      discordUsername = username;
    });
  }

  Future<void> _discordLogout() async {
    await DiscordPresenceManager.instance.stop();
    await DiscordTokenStore.clear();
    await storeSecureVal(SecureStorageKey.discordUsername, null);
    await writeSettings(SettingsModal(enableDiscordRichPresence: false));
    if (!mounted) return;
    setState(() {
      discordLoggedIn = false;
      hasDiscordToken = false;
      discordUsername = null;
    });
  }

  /// Asks for a Discord user token.
  ///
  /// The saved token is never read back into the field: replacing it means
  /// typing a new one, and removing it is a separate action. That keeps the
  /// credential out of the widget tree after the dialog closes.
  Future<bool> _promptDiscordToken(BuildContext context) async {
    final hadToken = await DiscordTokenStore.hasToken();
    if (!mounted) return false;
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appTheme.backgroundColor,
        title: const Text("Discord token"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Paste your own Discord account token. It is stored in this device's "
              "keystore and only used to set your Rich Presence.",
            ),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: hadToken ? "Token saved" : "Paste token",
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          if (hadToken)
            TextButton(
              onPressed: () async {
                await DiscordTokenStore.clear();
                await DiscordPresenceManager.instance.stop();
                if (context.mounted) Navigator.of(context).pop(true);
              },
              child: const Text("Remove"),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              final token = controller.text.trim();
              if (token.isEmpty) {
                Navigator.of(context).pop();
                return;
              }
              try {
                await DiscordTokenStore.save(token);
                await DiscordPresenceManager.instance.stop();
                if (context.mounted) Navigator.of(context).pop(true);
              } on DiscordPresenceException catch (e) {
                floatingSnackBar(e.message);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
    controller.clear();
    // Dispose after the dialog's exit transition: the field must not be
    // rebuilt with a dead controller.
    Future.delayed(const Duration(milliseconds: 500), controller.dispose);
    if (saved == true) {
      final tokenPresent = await DiscordTokenStore.hasToken();
      if (mounted) setState(() => hasDiscordToken = tokenPresent);
      return tokenPresent;
    }
    return false;
  }

  Future<bool> _confirmDiscordRisk(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appTheme.backgroundColor,
        title: const Text("Before you continue"),
        content: const Text(
          "Rich Presence on mobile signs in to the Discord gateway with your "
          "account's session. This is not an official Discord integration: using it "
          "can get the account suspended, and that session grants full access.\n\n"
          "Only continue with an account you are willing to risk.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("I understand"),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }
}
