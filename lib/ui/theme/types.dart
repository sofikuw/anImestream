import 'package:flutter/material.dart';

class ThemeItem {
  final String name;                      // Theme's name
  final AnimeStreamTheme theme;           // Dark variant of the theme
  final AnimeStreamTheme lightVariant;    // Light variant of the theme
  final int id;                           // Theme ID

  final bool dev;                        // Only for the dev versions (α, debug versions...)

  ThemeItem({
    required this.id,
    required this.name,
    required this.theme,
    required this.lightVariant,
    required this.dev,
  });
}

class AnimeStreamTheme {
  //core theme
  Color backgroundColor;               //background
  Color accentColor;                   //accent
  Color? secondaryAccent;              //second half of the Divergent split accent
  Color textMainColor;                 //for main texts
  Color textSubColor;                  //for description|sub texts
  Color backgroundSubColor;            //for card tints and some button highlights
  Color modalSheetBackgroundColor;     //for modal sheet (no issue being same as background)
  Color onAccent; 

  AnimeStreamTheme({
    required this.accentColor,
    required this.backgroundColor,
    required this.backgroundSubColor,
    required this.textMainColor,
    required this.textSubColor,
    required this.modalSheetBackgroundColor,
    required this.onAccent,
    this.secondaryAccent,
  });

  // Themes written before the fork only have one accent. Blend theirs toward
  // Divergent's ice cyan so the split header and navigation still read as two
  // tones instead of one flat bar.
  Color get secondaryColor => secondaryAccent ?? Color.lerp(accentColor, Color(0xff5EEAD4), 0.45)!;
}
