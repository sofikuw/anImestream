import 'package:flutter_test/flutter_test.dart';
import '../lib/core/extensions/models/manga_models.dart';

void main() {
  group('Manga Models Tests', () {
    test('MangaDetails parses JSON correctly with status and tags', () {
      final json = {
        'id': 'one_piece',
        'title': 'One Piece',
        'coverUrl': 'https://example.com/op.jpg',
        'description': 'Pirate adventure',
        'author': 'Eiichiro Oda',
        'status': 'Ongoing',
        'genres': ['Action', 'Adventure', 'Comedy'],
        'rating': 9.8,
        'totalChapters': 1100,
      };

      final manga = MangaDetails.fromJson(json, providerId: 'mangadex');
      expect(manga.id, 'one_piece');
      expect(manga.title, 'One Piece');
      expect(manga.status, MangaStatus.ongoing);
      expect(manga.genres.length, 3);
      expect(manga.rating, 9.8);
      expect(manga.providerId, 'mangadex');
    });

    test('MangaChapter parses numbers and sorting correctly', () {
      final c1 = MangaChapter.fromJson({'id': '1', 'number': 1.0, 'title': 'Ch 1'});
      final c2 = MangaChapter.fromJson({'id': '2', 'number': 2.5, 'title': 'Ch 2.5'});
      final c3 = MangaChapter.fromJson({'id': '3', 'number': 10, 'title': 'Ch 10'});

      final list = [c2, c3, c1];
      list.sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));

      expect(list.first.chapterNumber, 1.0);
      expect(list[1].chapterNumber, 2.5);
      expect(list.last.chapterNumber, 10.0);
    });

    test('ReadingProgress computes percentage correctly', () {
      final progress = ReadingProgress(
        mangaId: 'naruto',
        chapterId: 'c1',
        chapterNumber: 1.0,
        pageIndex: 11, // page 12 of 24
        totalPages: 24,
        updatedAt: DateTime.now(),
      );

      expect(progress.percent, 0.5);
    });
  });
}
