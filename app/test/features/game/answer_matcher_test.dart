import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/game/domain/answer_matcher.dart';
import 'package:app/features/game/domain/models.dart';

void main() {
  group('AnswerMatcher tests', () {
    late Question question;
    late AnswerMatcher matcher;

    setUp(() {
      question = const Question(
        id: 'q1',
        categoryId: 'c1',
        text: 'Kuzey Amerika ülkeleri',
        answers: [
          Answer(
            id: 'amerika',
            display: 'Amerika',
            aliases: ['amerika', 'abd', 'usa'],
          ),
          Answer(
            id: 'kanada',
            display: 'Kanada',
            aliases: ['kanada'],
          ),
          Answer(
            id: 'meksika',
            display: 'Meksika',
            aliases: ['meksika'],
          ),
        ],
      );
      matcher = AnswerMatcher(question);
    });

    test('alias eşleşmesi ("abd" -> amerika)', () {
      final result = matcher.check('abd', {});
      expect(result.isCorrect, isTrue);
      expect(result.answer?.display, equals('Amerika'));
    });

    test('tekrar eden cevap -> repeated', () {
      final used = {'amerika'};
      final result = matcher.check('usa', used);
      expect(result.isRepeated, isTrue);
      expect(result.answer?.display, equals('Amerika'));
    });

    test('olmayan cevap -> wrong', () {
      final result = matcher.check('fransa', {});
      expect(result.isWrong, isTrue);
      expect(result.answer, isNull);
    });

    test('boş girdi -> empty', () {
      final result1 = matcher.check('', {});
      expect(result1.isEmpty, isTrue);

      final result2 = matcher.check('   ', {});
      expect(result2.isEmpty, isTrue);

      final result3 = matcher.check('...', {});
      expect(result3.isEmpty, isTrue);
    });

    test('kalan cevap sayısı ve tükenme (isExhausted)', () {
      final used = <String>{};
      expect(matcher.remaining(used), equals(3));
      expect(matcher.isExhausted(used), isFalse);

      used.add('amerika');
      expect(matcher.remaining(used), equals(2));
      expect(matcher.isExhausted(used), isFalse);

      used.add('kanada');
      used.add('meksika');
      expect(matcher.remaining(used), equals(0));
      expect(matcher.isExhausted(used), isTrue);
    });
  });
}

