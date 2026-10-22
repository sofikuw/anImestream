import 'package:animestream/core/commons/enums/hiveEnums.dart';
import 'package:hive/hive.dart';

final String _boxName = HiveBox.animestream.boxName;

const int divergentThemeId = 13;
const String _themeMigrationKey = 'divergentThemeMigrated';

Future<int> getTheme() async {
  var box = await Hive.openBox(_boxName);
  if (!box.isOpen) {
    box = await Hive.openBox(_boxName);
  }

  dynamic selectedThemeId = box.get('theme');
  if (selectedThemeId is! int) {
    selectedThemeId = divergentThemeId;
    await box.put('theme', selectedThemeId);
  } else if (selectedThemeId == 1 && box.get(_themeMigrationKey) != true) {
    // Lime Zest was upstream's untouched default. Move existing installs to
    // Divergent once, but leave the one-time marker so choosing Lime Zest later
    // still sticks.
    selectedThemeId = divergentThemeId;
    await box.put('theme', selectedThemeId);
  }

  if (box.get(_themeMigrationKey) != true) {
    await box.put(_themeMigrationKey, true);
  }

  await box.close();
  return selectedThemeId;
}

//saves the theme
Future<void> setTheme(int themeId) async {
  var box = await Hive.openBox(_boxName);
  if (!box.isOpen) {
    box = await Hive.openBox(_boxName);
  }
  await box.put('theme', themeId);
  await box.put(_themeMigrationKey, true);
  await box.close();
  return;
}
