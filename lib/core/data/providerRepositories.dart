import 'package:animestream/core/anime/providers/providerRepository.dart';
import 'package:animestream/core/commons/enums/hiveEnums.dart';
import 'package:hive/hive.dart';

class ProviderRepositoriesPreferences {
  final String _boxKey = HiveBox.providerRepositories.boxName;

  static const String defaultRepositoryUrl =
      'https://raw.githubusercontent.com/sofikuw/anImestream-extensions/refs/heads/main/index.json';

  static const String _seededKey = '__default_repository_seeded__';

  Future<List<ProviderRepository>> listRepositories() async {
    final box = await Hive.openBox(_boxKey);
    try {
      // Seed once so a fresh install starts with the default catalog while a
      // user who removes it does not get it back on the next launch.
      if (box.get(_seededKey) != true) {
        if (box.values.whereType<Map>().isEmpty) {
          final defaultRepo = ProviderRepository.fromIndexUrl(defaultRepositoryUrl);
          await box.put(defaultRepo.id, defaultRepo.toMap());
        }
        await box.put(_seededKey, true);
      }
      return box.values
          .whereType<Map>()
          .map(
            (value) => ProviderRepository.fromMap(
              Map<String, dynamic>.from(value),
            ),
          )
          .toList(growable: false);
    } finally {
      await box.close();
    }
  }

  Future<void> saveRepository(ProviderRepository repository) async {
    final box = await Hive.openBox(_boxKey);
    try {
      await box.put(repository.id, repository.toMap());
    } finally {
      await box.close();
    }
  }

  Future<void> removeRepository(String repositoryId) async {
    final box = await Hive.openBox(_boxKey);
    try {
      await box.delete(repositoryId);
    } finally {
      await box.close();
    }
  }
}
