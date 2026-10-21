import 'package:animestream/ui/theme/types.dart';
import 'package:flutter/material.dart';

/// The fork's own theme: near-black ink, bone text, acid lime and ice cyan.
///
/// The two accents are the visual basis of the "split" motif used by the
/// header and the mobile navigation bar.
class Divergent implements ThemeItem {
  @override
  int get id => 13;

  @override
  bool get dev => false;

  @override
  String get name => "Divergent";

  @override
  AnimeStreamTheme get lightVariant => AnimeStreamTheme(
    accentColor: Color(0xff4E6B00),
    secondaryAccent: Color(0xff006B5F),
    backgroundColor: Color(0xffF4F2EA),
    backgroundSubColor: Color(0xffE2E0D6),
    textMainColor: Color(0xff15171C),
    textSubColor: Color(0xff575C63),
    modalSheetBackgroundColor: Color(0xffFBFAF5),
    onAccent: Color(0xffF7FFE0),
  );

  @override
  AnimeStreamTheme get theme => AnimeStreamTheme(
    accentColor: Color(0xffC8FF4D),
    secondaryAccent: Color(0xff5EEAD4),
    backgroundColor: Color(0xff0B0C10),
    backgroundSubColor: Color(0xff171A21),
    textMainColor: Color(0xffF2F0E9),
    textSubColor: Color(0xff9AA0A6),
    modalSheetBackgroundColor: Color(0xff12151B),
    onAccent: Color(0xff0B0C10),
  );
}
