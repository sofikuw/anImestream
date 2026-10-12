import 'package:animestream/core/anime/providers/providerRepository.dart';
import 'package:animestream/core/commons/enums/hiveEnums.dart';
import 'package:hive/hive.dart';

class ProviderRepositoriesPreferences {
  final String _boxKey = HiveBox.providerRepositories.boxName;

  Future<List<ProviderRepository>> listRepositories() async {
    final box = await Hive.openBox(_boxKey);
    try {
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
