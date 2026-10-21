import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/ui/pages/downloads.dart';
import 'package:animestream/ui/pages/settings.dart';
import 'package:flutter/material.dart';

const _sectionCodes = {
  'Feed': '01',
  'Explore': '02',
  'Search': '03',
  'Manga': '04',
};

Container buildHeader(String title, BuildContext context, {void Function()? afterNavigation}) {
  final code = _sectionCodes[title];

  return Container(
    padding: EdgeInsets.only(left: 20, top: 10, right: 20, bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [appTheme.accentColor, appTheme.secondaryColor],
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    "DIVERGENT",
                    style: TextStyle(
                      color: appTheme.accentColor,
                      fontFamily: "Poppins",
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 3.4,
                    ),
                  ),
                  if (code != null)
                    Text(
                      "  /  $code",
                      style: TextStyle(
                        color: appTheme.textSubColor,
                        fontFamily: "Poppins",
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1.4,
                      ),
                    ),
                ],
              ),
              SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: appTheme.textMainColor,
                  fontFamily: "Rubik",
                  fontWeight: FontWeight.bold,
                  fontSize: 30,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 8),
        Container(
          padding: EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: appTheme.backgroundSubColor.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: appTheme.textMainColor.withAlpha(20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _headerAction(
                tooltip: "Downloads",
                icon: Icons.download_rounded,
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => DownloadsPage())).then((val) {
                    if (afterNavigation != null) afterNavigation();
                  });
                },
              ),
              SizedBox(width: 2),
              _headerAction(
                tooltip: "Settings",
                icon: Icons.tune_rounded,
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => SettingsPage())).then((val) {
                    if (afterNavigation != null) afterNavigation();
                  });
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _headerAction({
  required String tooltip,
  required IconData icon,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: 40,
    height: 40,
    child: IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      iconSize: 24,
      splashRadius: 20,
      icon: Icon(icon, color: appTheme.textMainColor),
    ),
  );
}
