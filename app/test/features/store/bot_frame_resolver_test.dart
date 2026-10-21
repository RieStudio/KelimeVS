import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/utils/bot_frame_resolver.dart';

void main() {
  group('BotFrameResolver Tests', () {
    test('is deterministic: same name returns same frame consistently', () {
      final frame1 = BotFrameResolver.resolve('Ahmet');
      final frame2 = BotFrameResolver.resolve('Ahmet');
      final frame3 = BotFrameResolver.resolve('ahmet');
      final frame4 = BotFrameResolver.resolve('  Ahmet  ');

      expect(frame1, equals(frame2));
      expect(frame1, equals(frame3));
      expect(frame1, equals(frame4));
    });

    test('returns classic for empty or whitespace-only name', () {
      expect(BotFrameResolver.resolve(''), 'classic');
      expect(BotFrameResolver.resolve('   '), 'classic');
    });

    test('returns valid frame for all standard bot names', () {
      const names = [
        'Ahmet',
        'Zeynep',
        'Mert',
        'Elif',
        'Burak',
        'Can',
        'Selin',
        'Deniz',
        'Mehmet',
        'Ayşe',
      ];

      const validFrames = {
        'classic',
        'mint',
        'sunset',
        'ocean',
        'gold',
        'neon',
        'rainbow',
        'diamond',
      };

      for (final name in names) {
        final frame = BotFrameResolver.resolve(name);
        expect(validFrames.contains(frame), isTrue,
            reason: 'Bot $name resolved to invalid frame $frame');
      }
    });

    test('distribution across large pool contains classic predominantly', () {
      int classicCount = 0;
      final testNames = List.generate(200, (i) => 'BotPlayer_$i');

      for (final name in testNames) {
        if (BotFrameResolver.resolve(name) == 'classic') {
          classicCount++;
        }
      }

      // 70% nominal, should comfortably be over 50% in 200 samples
      expect(classicCount, greaterThan(100));
    });
  });
}

