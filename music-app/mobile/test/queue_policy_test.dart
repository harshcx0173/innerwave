import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/audio/queue_policy.dart';

void main() {
  test('song discovery shelves start a song-based radio queue', () {
    const radioTitles = [
      'Quick picks',
      'Because you listened',
      'Covers and remixes',
      'Trending songs for you',
      'Long listens',
    ];

    for (final title in radioTitles) {
      expect(
        startsSongRadioQueue(shelfId: 'unknown', shelfTitle: title),
        isTrue,
        reason: title,
      );
    }
  });

  test('collection shelves keep their visible track context', () {
    expect(
      startsSongRadioQueue(
        shelfId: 'albums-for-you',
        shelfTitle: 'Albums for you',
      ),
      isFalse,
    );
  });
}
