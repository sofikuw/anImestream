import 'dart:io';

import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/app/update.dart';
import 'package:animestream/core/commons/utils.dart';
import 'package:animestream/core/data/downloadHistory.dart';
import 'package:animestream/ui/models/providers/mainNavProvider.dart';
import 'package:animestream/ui/models/widgets/bottomBar.dart';
import 'package:animestream/ui/models/widgets/floatyBar/controller.dart';
import 'package:animestream/ui/models/widgets/floatyBar/floatyBarView.dart';
import 'package:animestream/ui/models/widgets/floatyBar/floatyBottomBar.dart';
import 'package:animestream/ui/models/snackBar.dart';
import 'package:animestream/ui/pages/discover.dart';
import 'package:animestream/ui/pages/home.dart';
import 'package:animestream/ui/pages/search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Three tabs: Home, Discover, Search.
///
/// Manga has no tab of its own. It is a content type that appears inside the
/// existing tabs -- rails on Discover, results in Search, a Continue Reading row
/// on Home -- so the navigation is back to the three destinations it had before
/// manga was added, and the Manga tab's index-3 slot is gone.
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => MainNavigatorState();
}

class MainNavigatorState extends State<MainNavigator> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();

    final provider = context.read<MainNavProvider>();

    isTv().then((value) => provider.tv = value);

    // open the box for the whole app life time!
    DownloadHistory.initBox();

    //check for app updates & show prompt
    checkForUpdates().then((data) => {
          if (data != null)
            {
              showUpdateSheet(
                context,
                data,
                // forceTrigger: true
              ),
            }
        });

    // load the stuff
    provider.init();
  }

  final _floatyBarController = FloatyBottomBarController(length: 3);
  final _barController = AnimeStreamBottomBarController(length: 3);

  bool popInvoked = false;

  late MainNavProvider mainNavProvider;

  //reset the popInvoke
  Future<void> popTimeoutWindow() async {
    await Future.delayed(Duration(seconds: 3));
    popInvoked = false;
  }

  @override
  Widget build(BuildContext context) {
    mainNavProvider = context.watch<MainNavProvider>();

    double blurSigmaValue = currentUserSettings!.navbarTranslucency ?? 5;
    if (blurSigmaValue <= 1) {
      blurSigmaValue = blurSigmaValue * 10;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, res) async {
        // Index 0 is Home. With the Manga tab gone, Search is the last index --
        // anything other than Home returns there first, which also covers a
        // user who was on Search when they hit back.
        if (_barController.currentIndex != 0) {
          _barController.currentIndex = 0;
          return;
        }

        //exit the app if back is pressed again within 3 sec window
        if (popInvoked) return await SystemNavigator.pop();

        floatingSnackBar("Hit back once again to exit the app");
        popInvoked = true;
        popTimeoutWindow();
      },
      child: Scaffold(
        body: MediaQuery.of(context).orientation == Orientation.landscape || Platform.isWindows || Platform.isLinux
            ? Row(
                children: [
                  NavigationRail(
                    onDestinationSelected: (value) {
                      _barController.currentIndex = value;
                      setState(() {});
                    },
                    backgroundColor: appTheme.backgroundColor,
                    elevation: 1,
                    indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    indicatorColor: appTheme.accentColor,
                    destinations: [
                      NavigationRailDestination(
                        icon: Icon(
                          Icons.home,
                          color: _barController.currentIndex == 0 ? appTheme.onAccent : appTheme.textMainColor,
                        ),
                        label: Text(
                          "Home",
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                      NavigationRailDestination(
                        icon: Icon(
                          Icons.auto_awesome,
                          color: _barController.currentIndex == 1 ? appTheme.onAccent : appTheme.textMainColor,
                        ),
                        label: Text(
                          "Discover",
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.search_rounded,
                            color: _barController.currentIndex == 2 ? appTheme.onAccent : appTheme.textMainColor),
                        label: Text(
                          "Search",
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                    selectedIndex: _barController.currentIndex,
                  ),
                  Expanded(
                    child: BottomBarView(
                      controller: _barController,
                      children: [
                        Home(
                          mainNavProvider: mainNavProvider,
                        ),
                        Discover(
                          mainNavProvider: mainNavProvider,
                        ),
                        Search(),
                      ],
                    ),
                  ),
                ],
              )
            : _bottomBar(context, blurSigmaValue),
      ),
    );
  }

  Widget _bottomBar(BuildContext context, double blurSigmaValue) {
    return (currentUserSettings?.useOldNavbar ?? false)
        ? Stack(
            children: [
              BottomBarView(
                controller: _barController,
                children: [
                  Home(
                    key: ValueKey("0"),
                    mainNavProvider: mainNavProvider,
                  ),
                  Discover(
                    key: ValueKey("1"),
                    mainNavProvider: mainNavProvider,
                  ),
                  Search(
                    key: ValueKey("2"),
                  ),
                ],
              ),
              AnimeStreamBottomBar(
                borderRadius: 12,
                accentColor: appTheme.accentColor,
                backgroundColor:
                    appTheme.backgroundSubColor.withValues(alpha: currentUserSettings?.navbarTranslucency ?? 0.5),
                items: [
                  BottomBarItem(title: 'Home', icon: Icon(Icons.home)),
                  BottomBarItem(title: 'Discover', icon: Icon(Icons.auto_awesome)),
                  BottomBarItem(title: 'Search', icon: Icon(Icons.search)),
                ],
                controller: _barController,
              )
            ],
          )
        : Stack(
            children: [
              FloatyBarView(
                controller: _floatyBarController,
                children: [
                  Home(
                    key: ValueKey("0"),
                    mainNavProvider: mainNavProvider,
                  ),
                  Discover(
                    key: ValueKey("1"),
                    mainNavProvider: mainNavProvider,
                  ),
                  Search(
                    key: ValueKey("2"),
                  ),
                ],
              ),
              FloatyBottomBar(
                controller: _floatyBarController,
                accentColor: appTheme.accentColor,
                backgroundColor:
                    appTheme.backgroundSubColor.withValues(alpha: currentUserSettings?.navbarTranslucency ?? 0.5),
                items: [
                  FloatyBarItem(title: 'Home', icon: Icons.home),
                  FloatyBarItem(title: 'Discover', icon: Icons.auto_awesome),
                  FloatyBarItem(title: 'Search', icon: Icons.search),
                ],
              )
            ],
          );
  }
}