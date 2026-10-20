// Saf Dart betiği - Ortak test vektörlerini üretir.
// Çalıştırma: dart run tool/export_test_vectors.dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app/features/game/domain/answer_matcher.dart';
import 'package:app/features/game/domain/match/match_config.dart';
import 'package:app/features/game/domain/match/match_engine.dart';
import 'package:app/features/game/domain/match/match_events.dart';
import 'package:app/features/game/domain/match/match_state.dart';
import 'package:app/features/game/domain/match/near_miss.dart';
import 'package:app/features/game/domain/models.dart';
import 'package:app/features/game/domain/text_normalizer.dart';

Directory _findOutputDirectory() {
  final candidate1 = Directory('shared/test-vectors');
  if (candidate1.existsSync()) return candidate1;

  final candidate2 = Directory('../shared/test-vectors');
  if (candidate2.existsSync()) return candidate2;

  candidate2.createSync(recursive: true);
  return candidate2;
}

void main() {
  final outDir = _findOutputDirectory();
  print('Test vektörleri hedef dizini: ${outDir.absolute.path}');

  final normalizerCases = _buildNormalizerVectors();
  _writeJson(File('${outDir.path}/normalizer.json'), {
    'version': 1,
    'description':
        'TextNormalizer test vectors for KelimeVS Turkish text normalization',
    'totalCases': normalizerCases.length,
    'cases': normalizerCases,
  });
  print('✓ normalizer.json üretildi: ${normalizerCases.length} durum');

  final matcherCases = _buildMatcherVectors();
  _writeJson(File('${outDir.path}/matcher.json'), {
    'version': 1,
    'description':
        'AnswerMatcher test vectors for KelimeVS answer checking with alias indexing',
    'totalCases': matcherCases.length,
    'cases': matcherCases,
  });
  print('✓ matcher.json üretildi: ${matcherCases.length} durum');

  final nearMissCases = _buildNearMissVectors();
  _writeJson(File('${outDir.path}/near_miss.json'), {
    'version': 1,
    'description':
        'NearMissCalculator test vectors for Damerau-Levenshtein distances and thresholds',
    'totalCases': nearMissCases.length,
    'cases': nearMissCases,
  });
  print('✓ near_miss.json üretildi: ${nearMissCases.length} durum');

  final visibilityCases = _buildVisibilityVectors();
  _writeJson(File('${outDir.path}/visibility.json'), {
    'version': 1,
    'description':
        'visibleAttempts test vectors for client-side attempt visibility filtering',
    'totalCases': visibilityCases.length,
    'cases': visibilityCases,
  });
  print('✓ visibility.json üretildi: ${visibilityCases.length} durum');

  final scenarioCases = _buildEngineScenarios();
  _writeJson(File('${outDir.path}/engine_scenarios.json'), {
    'version': 1,
    'description':
        'MatchEngine complete step-by-step match scenarios for state and event verification',
    'totalScenarios': scenarioCases.length,
    'scenarios': scenarioCases,
  });
  print('✓ engine_scenarios.json üretildi: ${scenarioCases.length} senaryo');

  print('\nTüm test vektörleri başarıyla üretildi.');
}

void _writeJson(File file, Map<String, dynamic> data) {
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(data)}\n');
}

// ============================================================================
// 1. NORMALIZER VECTORS
// ============================================================================

List<Map<String, dynamic>> _buildNormalizerVectors() {
  const inputs = <String>[
    // 1. Türkçe büyük/küçük harf
    'ISPANAK',
    'ıspanak',
    'İSTANBUL',
    'istanbul',
    'IĞDIR',
    'Irmak',
    'İZMİR',
    'DİYARBAKIR',
    'ŞANLIURFA',
    'ÇANAKKALE',
    'GÜMÜŞHANE',
    'KIRIKKALE',
    'AĞRI',
    'ÖMER',
    'ÜZÜM',
    'ığdır',
    'şeker',
    'çiçek',
    'ağaç',
    'öğretmen',
    // 2. Aksan katlama (ç->c, ğ->g, ı->i, ö->o, ş->s, ü->u)
    'çarşamba',
    'çiğdem',
    'dağlık',
    'ılık',
    'ışık',
    'kömür',
    'gözlük',
    'şömine',
    'üçgen',
    'üzüntü',
    // 3. Şapkalı harfler (â->a, î->i, û->u)
    'hâkîm',
    'kâğıt',
    'millî',
    'sükût',
    'rüzgâr',
    'hâlâ',
    'ÂŞIK',
    'lâle',
    'dâhil',
    'mahkûm',
    'resmî',
    'hilâl',
    'sükûnet',
    'müşfik',
    // 4. Noktalama, parantez, sembol temizleme
    'elma, armut.',
    'ankara!',
    'ankara-izmir',
    "ali'nin",
    '(parantez)',
    '"tırnak"',
    'soru?',
    'noktalı;virgül:',
    'e-posta@test.com',
    'fiyat/adet',
    'yüzde%yüz',
    've&veya',
    'alt_tire',
    'eşittir=değer',
    'dalga~işareti',
    // 5. C, C++, C# ayrımı
    'c',
    'c++',
    'C++',
    'c#',
    'C#',
    'c + +',
    'c #',
    'c++ ve c#',
    '+++c',
    '###',
    'dil: c++',
    'programlama: c#',
    // 6. Ardışık boşluk ve kenar boşlukları
    '   elma   ',
    '   elma    armut   ',
    'elma\t\narmut',
    '  \t\r\n  ',
    'bir   iki   uc',
    // 7. Rakamlar
    '123',
    'kelime 2026',
    '3.14',
    '99+1',
    'f16',
    // 8. Boş metin ve yalnızca noktalama
    '',
    ' ',
    '   ',
    '??!!',
    '...',
    '---___---',
    '///\\\\\\',
    // 9. Uzun metin ve karışık alfabe
    'bu cok uzun bir cumledir ve normalizasyon testi icin ozenle hazirlanmistir',
    'PÖÇĞÜŞI öçğüşi İIÂÎÛ âîû',
    // 10. Emoji ve semboller
    '🍎 elma 🍌 muz',
    'türkiye 🇹🇷',
    '🎉🎊🥳',
    // 11. Birleşik işaretler (combining marks)
    'e\u0301',
    'c\u0327',
    'g\u0306',
    'a\u0302',
    'u\u0308',
    'o\u0308',
    's\u0327',
    'i\u0307',
    'cafe\u0301',
  ];

  final result = <Map<String, dynamic>>[];
  for (int i = 0; i < inputs.length; i++) {
    final input = inputs[i];
    final expected = TextNormalizer.normalize(input);
    result.add({
      'id': 'norm_${(i + 1).toString().padLeft(3, '0')}',
      'input': input,
      'expected': expected,
    });
  }
  return result;
}

// ============================================================================
// 2. MATCHER VECTORS
// ============================================================================

Question _makeQuestion({
  required String id,
  required String categoryId,
  required String title,
  required Map<String, List<String>> acceptableAnswers,
}) {
  return Question(
    id: id,
    categoryId: categoryId,
    text: title,
    answers: acceptableAnswers.entries.map((entry) {
      final normId = TextNormalizer.normalize(entry.key);
      final normAliases = {
        if (normId.isNotEmpty) normId,
        ...entry.value.map(TextNormalizer.normalize).where((s) => s.isNotEmpty),
      }.toList();

      return Answer(
        id: normId,
        display: entry.key,
        aliases: normAliases,
      );
    }).toList(),
  );
}

Map<String, dynamic> _questionToJson(Question q) {
  return {
    'id': q.id,
    'categoryId': q.categoryId,
    'title': q.text,
    'answers': q.answers
        .map((a) => {
              'id': a.id,
              'display': a.display,
              'aliases': a.aliases,
            })
        .toList(),
  };
}

List<Map<String, dynamic>> _buildMatcherVectors() {
  final qG20 = _makeQuestion(
    id: 'q_g20',
    categoryId: 'genel_kultur',
    title: 'G20 Ülkeleri',
    acceptableAnswers: {
      'Güney Kore': ['güney kore', 'kore'],
      'Suudi Arabistan': ['suudi arabistan', 'arabistan'],
      'Almanya': ['almanya'],
      'Fransa': ['fransa'],
      'İtalya': ['italya'],
      'Çin': ['çin'],
      'Japonya': ['japonya'],
      'Kanada': ['kanada'],
    },
  );

  final qLangs = _makeQuestion(
    id: 'q_langs',
    categoryId: 'bilim_teknoloji',
    title: 'Programlama Dilleri',
    acceptableAnswers: {
      'C': ['c'],
      'C++': ['c++'],
      'C#': ['c#'],
      'Python': ['python'],
      'JavaScript': ['javascript', 'js'],
      'Dart': ['dart'],
    },
  );

  final qFruits = _makeQuestion(
    id: 'q_fruits',
    categoryId: 'doga',
    title: 'Meyveler',
    acceptableAnswers: {
      'Elma': ['elma'],
      'Armut': ['armut'],
      'Muz': ['muz'],
      'Çilek': ['çilek'],
      'Portakal': ['portakal'],
    },
  );

  final testCasesDefinition = <(Question, String, List<String>, String)>[
    // G20 Sorusunda testler
    (qG20, 'Güney Kore', [], 'exact display match'),
    (qG20, 'guney kore', [], 'normalized display match'),
    (qG20, 'kore', [], 'alias match'),
    (qG20, 'KORE', [], 'uppercase alias match'),
    (qG20, 'suudi arabistan', [], 'multi-word exact match'),
    (qG20, 'arabistan', [], 'multi-word alias match'),
    (qG20, 'Almanya', ['almanya'], 'repeated answer when already used'),
    (qG20, 'almanya', ['almanya'], 'repeated lowercase when used'),
    (qG20, 'kore', ['guney kore'], 'repeated alias when primary is used'),
    (qG20, 'fransa', [], 'exact match fransa'),
    (qG20, 'italya', [], 'exact match italya'),
    (qG20, 'cin', [], 'accent folded cin match for Çin'),
    (qG20, 'ÇİN', [], 'uppercase Çin match'),
    (qG20, 'japonya', [], 'exact match japonya'),
    (qG20, 'kanada', [], 'exact match kanada'),
    (qG20, 'almany', [], 'near miss to unused almanya (dist 1, len 7)'),
    (qG20, 'almany', ['almanya'], 'wrong but NOT close because almanya is already used'),
    (qG20, 'frnasa', [], 'near miss transposition for fransa (dist 1, len 6)'),
    (qG20, 'suud arabistn', [], 'near miss for suudi arabistan (dist 2, len 15)'),
    (qG20, 'cna', [], 'wrong 3-char word with typo (threshold <= 3 is 0, isClose false)'),
    (qG20, 'muz', [], 'completely wrong fruit word on G20 countries'),
    (qG20, 'ispanya', [], 'wrong country not in G20 list'),
    (qG20, '', [], 'empty string input'),
    (qG20, '   ', [], 'whitespace only input'),
    (qG20, '??!!', [], 'punctuation only input'),
    (qG20, 'kore!', [], 'punctuation stripped alias match'),

    // Programlama Dilleri Sorusunda testler
    (qLangs, 'c', [], 'exact c match'),
    (qLangs, 'c++', [], 'exact c++ match'),
    (qLangs, 'C++', [], 'uppercase C++ match'),
    (qLangs, 'c#', [], 'exact c# match'),
    (qLangs, 'C#', [], 'uppercase C# match'),
    (qLangs, 'c+ +', [], 'spaced c+ + is not c++'),
    (qLangs, 'python', [], 'exact python match'),
    (qLangs, 'js', [], 'alias js match for JavaScript'),
    (qLangs, 'javascript', [], 'display match for JavaScript'),
    (qLangs, 'dart', [], 'exact dart match'),
    (qLangs, 'pythno', [], 'near miss transposition for python (dist 1, len 6)'),
    (qLangs, 'drat', [], 'near miss transposition for dart (dist 1, len 4)'),
    (qLangs, 'c+', [], 'c+ typo (len 2 <= 3, isClose false)'),
    (qLangs, 'c', ['c'], 'repeated c'),
    (qLangs, 'c++', ['c++'], 'repeated c++'),

    // Meyveler Sorusunda testler
    (qFruits, 'elma', [], 'exact elma match'),
    (qFruits, 'elam', [], 'near miss transposition for elma (dist 1, len 4)'),
    (qFruits, 'armut', [], 'exact armut match'),
    (qFruits, 'armud', [], 'near miss substitution for armut (dist 1, len 5)'),
    (qFruits, 'muz', [], 'exact muz match'),
    (qFruits, 'mzu', [], '3-letter typo for muz (isClose false)'),
    (qFruits, 'cilek', [], 'accent folded cilek match for Çilek'),
    (qFruits, 'portakal', [], 'exact portakal match'),
    (qFruits, 'portakla', [], 'near miss transposition for portakal (dist 1, len 8)'),
  ];

  final result = <Map<String, dynamic>>[];
  for (int i = 0; i < testCasesDefinition.length; i++) {
    final (question, input, usedIdsList, desc) = testCasesDefinition[i];
    final usedSet = usedIdsList.toSet();
    final matcher = AnswerMatcher(question);
    final matchResult = matcher.check(input, usedSet);

    String expectedResult;
    String? expectedAnswerId;
    switch (matchResult) {
      case MatchResultCorrect(:final answer):
        expectedResult = 'correct';
        expectedAnswerId = answer.id;
      case MatchResultRepeated(:final answer):
        expectedResult = 'repeated';
        expectedAnswerId = answer.id;
      case MatchResultWrong():
        expectedResult = 'wrong';
        expectedAnswerId = null;
      case MatchResultEmpty():
        expectedResult = 'empty';
        expectedAnswerId = null;
    }

    bool expectedIsClose = false;
    if (expectedResult == 'wrong') {
      final normalized = TextNormalizer.normalize(input);
      final unusedAliases = question.answers
          .where((a) => !usedSet.contains(a.id))
          .map((a) => a.aliases);
      expectedIsClose = NearMissCalculator.isNearMiss(
        normalizedInput: normalized,
        unusedAnswerAliases: unusedAliases,
      );
    }

    result.add({
      'id': 'match_${(i + 1).toString().padLeft(3, '0')}',
      'description': desc,
      'question': _questionToJson(question),
      'input': input,
      'usedAnswerIds': usedIdsList,
      'expectedResult': expectedResult,
      'expectedAnswerId': expectedAnswerId,
      'expectedIsClose': expectedIsClose,
    });
  }

  return result;
}

// ============================================================================
// 3. NEAR MISS VECTORS
// ============================================================================

List<Map<String, dynamic>> _buildNearMissVectors() {
  const pairs = <(String, String, String)>[
    // target length <= 3 (threshold = 0)
    ('van', 'van', 'exact match 3 chars'),
    ('vna', 'van', 'transposition 3 chars (threshold 0 -> false)'),
    ('su', 'sur', 'insertion 3 chars (threshold 0 -> false)'),
    ('sur', 'su', 'deletion from 2 chars (threshold 0 -> false)'),
    ('cin', 'can', 'substitution 3 chars (threshold 0 -> false)'),
    ('a', 'b', 'substitution 1 char (threshold 0 -> false)'),
    ('ali', 'elo', 'distance 2 on 3 chars -> false'),

    // target length 4..8 (threshold = 1)
    ('armut', 'armut', 'exact match 5 chars -> dist 0, close false'),
    ('armud', 'armut', 'substitution 5 chars -> dist 1, close true'),
    ('armt', 'armut', 'deletion 5 chars -> dist 1, close true'),
    ('armutt', 'armut', 'insertion 5 chars -> dist 1, close true'),
    ('amrut', 'armut', 'transposition 5 chars -> dist 1, close true'),
    ('elam', 'elma', 'transposition 4 chars -> dist 1, close true'),
    ('elma', 'elma', 'exact match 4 chars -> dist 0, close false'),
    ('kedi', 'kedi', 'exact match 4 chars -> dist 0, close false'),
    ('ked', 'kedi', 'deletion 4 chars -> dist 1, close true'),
    ('kitpa', 'kitap', 'transposition 5 chars -> dist 1, close true'),
    ('kitap', 'kitpa', 'transposition reverse -> dist 1, close true'),
    ('amt', 'armut', '2 edits on 5 chars -> dist 2, close false'),
    ('arxyz', 'armut', '3 edits on 5 chars -> dist 3, close false'),
    ('ankraa', 'ankara', 'transposition 6 chars -> dist 1, close true'),
    ('istanbl', 'istanbul', 'deletion 8 chars -> dist 1, close true'),
    ('istanb', 'istanbul', '2 deletions on 8 chars -> dist 2, close false'),
    ('frnasa', 'fransa', 'transposition 6 chars -> dist 1, close true'),
    ('italya', 'italya', 'exact match 6 chars -> dist 0, close false'),
    ('italyo', 'italya', 'substitution 6 chars -> dist 1, close true'),

    // target length >= 9 (threshold = 2)
    ('avusturalya', 'avustralya', 'insertion 10 chars -> dist 1, close true'),
    ('avusturalyo', 'avustralya', '2 edits 10 chars -> dist 2, close true'),
    ('avusturalyox', 'avustralya', '3 edits 10 chars -> dist 3, close false'),
    ('madagaskra', 'madagaskar', 'transposition 10 chars -> dist 1, close true'),
    ('madagsakra', 'madagaskar', '2 edits 10 chars -> dist 2, close true'),
    ('madgaskra', 'madagaskar', '2 edits 10 chars -> dist 2, close true'),
    ('madgaskr', 'madagaskar', '3 edits 10 chars -> dist 3, close false'),
    ('guney afrika', 'guney afrika', 'exact 12 chars -> dist 0, close false'),
    ('guney afrik', 'guney afrika', 'deletion 12 chars -> dist 1, close true'),
    ('guney afrikx', 'guney afrika', '2 edits 12 chars -> dist 2, close true'),
    ('guny afrk', 'guney afrika', '3 edits 12 chars -> dist 3, close false'),

    // Multi-word strings
    ('suudi arabistn', 'suudi arabistan', 'deletion 15 chars -> dist 1, close true'),
    ('suud arabistn', 'suudi arabistan', '2 deletions 15 chars -> dist 2, close true'),
    ('suud arabstn', 'suudi arabistan', '3 deletions 15 chars -> dist 3, close false'),
    ('kuzey makedoyna', 'kuzey makedonya', 'transposition 15 chars -> dist 1, close true'),

    // Empty and edge cases
    ('', 'elma', 'empty input vs 4 chars -> dist 4, close false'),
    ('elma', '', 'input vs empty target -> dist 4, close false'),
    ('', '', 'empty vs empty -> dist 0, close false'),
  ];

  final result = <Map<String, dynamic>>[];
  for (int i = 0; i < pairs.length; i++) {
    final (w1, w2, desc) = pairs[i];
    final targetLen = w2.length;
    final maxDist = NearMissCalculator.maxAllowedDistance(targetLen);
    final dist = NearMissCalculator.distance(w1, w2);
    final isClose = dist > 0 && dist <= maxDist;

    result.add({
      'id': 'nm_${(i + 1).toString().padLeft(3, '0')}',
      'description': desc,
      'word1': w1,
      'word2': w2,
      'targetLength': targetLen,
      'maxAllowedDistance': maxDist,
      'distance': dist,
      'isClose': isClose,
    });
  }

  return result;
}

// ============================================================================
// 4. VISIBILITY VECTORS
// ============================================================================

List<Map<String, dynamic>> _buildVisibilityVectors() {
  TurnAttempt makeAttempt({
    required String playerId,
    required String rawInput,
    required AttemptResultType resultType,
    String? answerId,
    required int nowMs,
    bool isClose = false,
    bool hintShown = false,
  }) {
    return TurnAttempt(
      playerId: playerId,
      rawInput: rawInput,
      resultType: resultType,
      answerId: answerId,
      nowMs: nowMs,
      isClose: isClose,
      hintShown: hintShown,
    );
  }

  Map<String, dynamic> attemptToJson(TurnAttempt a) {
    return {
      'playerId': a.playerId,
      'rawInput': a.rawInput,
      'resultType': a.resultType.name,
      if (a.answerId != null) 'answerId': a.answerId,
      'nowMs': a.nowMs,
      'isClose': a.isClose,
      'hintShown': a.hintShown,
    };
  }

  final a1Correct = makeAttempt(
    playerId: 'p1',
    rawInput: 'elma',
    resultType: AttemptResultType.correct,
    answerId: 'elma',
    nowMs: 1000,
  );
  final a1WrongNormal = makeAttempt(
    playerId: 'p1',
    rawInput: 'kiraz',
    resultType: AttemptResultType.wrong,
    nowMs: 2000,
    isClose: false,
    hintShown: false,
  );
  final a1NearMissHint = makeAttempt(
    playerId: 'p1',
    rawInput: 'elam',
    resultType: AttemptResultType.nearMiss,
    nowMs: 3000,
    isClose: true,
    hintShown: true,
  );
  final a1NearMissNoHint = makeAttempt(
    playerId: 'p1',
    rawInput: 'armud',
    resultType: AttemptResultType.wrong,
    nowMs: 4000,
    isClose: true,
    hintShown: false,
  );
  final a2Correct = makeAttempt(
    playerId: 'p2',
    rawInput: 'armut',
    resultType: AttemptResultType.correct,
    answerId: 'armut',
    nowMs: 5000,
  );
  final a2WrongNormal = makeAttempt(
    playerId: 'p2',
    rawInput: 'kavun',
    resultType: AttemptResultType.wrong,
    nowMs: 6000,
    isClose: false,
    hintShown: false,
  );
  final a2NearMissHint = makeAttempt(
    playerId: 'p2',
    rawInput: 'amrut',
    resultType: AttemptResultType.nearMiss,
    nowMs: 7000,
    isClose: true,
    hintShown: true,
  );
  final a2NearMissNoHint = makeAttempt(
    playerId: 'p2',
    rawInput: 'mzu',
    resultType: AttemptResultType.wrong,
    nowMs: 8000,
    isClose: true,
    hintShown: false,
  );
  final a1Repeated = makeAttempt(
    playerId: 'p1',
    rawInput: 'elma',
    resultType: AttemptResultType.repeated,
    answerId: 'elma',
    nowMs: 9000,
  );

  final testDefs = <(List<TurnAttempt>, String, bool, String)>[
    // 1-3. Empty list tests
    ([], 'p1', true, 'Empty attempts list during active round'),
    ([], 'p1', false, 'Empty attempts list during ended round'),
    ([], 'p2', true, 'Empty attempts list for p2'),

    // 4-7. Round ended: everything visible to everyone
    (
      [a1Correct, a1NearMissHint, a1NearMissNoHint, a2WrongNormal],
      'p1',
      false,
      'Ended round: all visible to p1',
    ),
    (
      [a1Correct, a1NearMissHint, a1NearMissNoHint, a2WrongNormal],
      'p2',
      false,
      'Ended round: all visible to p2',
    ),
    (
      [a1NearMissHint, a2NearMissHint],
      'p1',
      false,
      'Ended round: hintShown attempts are visible to p1',
    ),
    (
      [a1NearMissNoHint, a2NearMissNoHint],
      'p1',
      false,
      'Ended round: isClose attempts are visible to opponent p1',
    ),

    // 8-11. Single attempt active round
    ([a1Correct], 'p1', true, 'Single correct attempt seen by author p1'),
    ([a1Correct], 'p2', true, 'Single correct attempt seen by opponent p2'),
    ([a1WrongNormal], 'p1', true, 'Normal wrong attempt seen by author p1'),
    ([a1WrongNormal], 'p2', true, 'Normal wrong attempt seen by opponent p2'),

    // 12-15. Near miss with hint shown: hidden from EVERYONE during active round
    ([a1NearMissHint], 'p1', true, 'HintShown near miss is hidden from author p1'),
    ([a1NearMissHint], 'p2', true, 'HintShown near miss is hidden from opponent p2'),
    (
      [a1NearMissHint, a2NearMissHint],
      'p1',
      true,
      'Multiple HintShown near misses hidden from p1',
    ),
    (
      [a1NearMissHint, a2NearMissHint],
      'p2',
      true,
      'Multiple HintShown near misses hidden from p2',
    ),

    // 16-19. Near miss WITHOUT hint shown (quota exhausted): visible to author, hidden from opponent
    ([a1NearMissNoHint], 'p1', true, 'NoHint near miss visible to author p1'),
    ([a1NearMissNoHint], 'p2', true, 'NoHint near miss hidden from opponent p2'),
    ([a2NearMissNoHint], 'p2', true, 'NoHint near miss visible to author p2'),
    ([a2NearMissNoHint], 'p1', true, 'NoHint near miss hidden from opponent p1'),

    // 20-22. Mixed attempts in active round: author vs opponent view
    (
      [
        a1Correct, // 0: visible to both
        a1NearMissHint, // 1: hidden from both
        a1NearMissNoHint, // 2: visible only to p1
        a1WrongNormal, // 3: visible to both
        a2Correct, // 4: visible to both
        a2NearMissHint, // 5: hidden from both
        a2NearMissNoHint, // 6: visible only to p2
        a2WrongNormal, // 7: visible to both
      ],
      'p1',
      true,
      'Mixed attempts: p1 view during active round',
    ),
    (
      [
        a1Correct, // 0
        a1NearMissHint, // 1
        a1NearMissNoHint, // 2
        a1WrongNormal, // 3
        a2Correct, // 4
        a2NearMissHint, // 5
        a2NearMissNoHint, // 6
        a2WrongNormal, // 7
      ],
      'p2',
      true,
      'Mixed attempts: p2 view during active round',
    ),
    (
      [
        a1Correct,
        a1NearMissHint,
        a1NearMissNoHint,
        a1WrongNormal,
        a2Correct,
        a2NearMissHint,
        a2NearMissNoHint,
        a2WrongNormal,
      ],
      'p1',
      false,
      'Mixed attempts: p1 view after round ended',
    ),

    // 23-25. Repeated answer and edge cases
    ([a1Repeated], 'p1', true, 'Repeated answer visible to author p1'),
    ([a1Repeated], 'p2', true, 'Repeated answer visible to opponent p2'),
    ([a1Repeated, a1NearMissNoHint, a2NearMissNoHint], 'p1', true, 'Repeated and close mix for p1'),
  ];

  final result = <Map<String, dynamic>>[];
  for (int i = 0; i < testDefs.length; i++) {
    final (attempts, viewerId, roundActive, desc) = testDefs[i];
    final record = RoundRecord(
      questionId: 'q_test',
      starterPlayerId: 'p1',
      attempts: attempts,
      winnerId: null,
      reason: RoundEndReason.timeout,
    );

    final visible = visibleAttempts(record, viewerId, roundActive);
    final visibleIndices = <int>[];
    for (int idx = 0; idx < attempts.length; idx++) {
      if (visible.contains(attempts[idx])) {
        visibleIndices.add(idx);
      }
    }

    result.add({
      'id': 'vis_${(i + 1).toString().padLeft(3, '0')}',
      'description': desc,
      'attempts': attempts.map(attemptToJson).toList(),
      'viewerId': viewerId,
      'roundActive': roundActive,
      'expectedVisibleIndices': visibleIndices,
    });
  }

  return result;
}

// ============================================================================
// 5. ENGINE SCENARIOS
// ============================================================================

Map<String, dynamic> _eventToJson(MatchEvent e) {
  return switch (e) {
    AnswerAccepted(:final playerId, :final answerDisplay) => {
        'type': 'AnswerAccepted',
        'playerId': playerId,
        'answerDisplay': answerDisplay,
      },
    NearMiss(:final playerId) => {
        'type': 'NearMiss',
        'playerId': playerId,
      },
    WrongAnswer(:final playerId, :final rawInput) => {
        'type': 'WrongAnswer',
        'playerId': playerId,
        'rawInput': rawInput,
      },
    AlreadySaid(:final playerId, :final answerDisplay) => {
        'type': 'AlreadySaid',
        'playerId': playerId,
        'answerDisplay': answerDisplay,
      },
    RoundWon(:final winnerId, :final reason) => {
        'type': 'RoundWon',
        'winnerId': winnerId,
        'reason': reason.name,
      },
    RoundDrawn(:final reason) => {
        'type': 'RoundDrawn',
        'reason': reason.name,
      },
    MatchFinished(:final winnerId, :final reason) => {
        'type': 'MatchFinished',
        'winnerId': winnerId,
        'reason': reason,
      },
    Ignored(:final reason) => {
        'type': 'Ignored',
        'reason': reason,
      },
  };
}

Map<String, dynamic> _stateSnapshot(MatchState state) {
  final usedList = state.usedAnswerIds.toList()..sort();
  return {
    'phase': state.phase.name,
    'turnPlayerId': state.turnPlayerId,
    'scores': Map<String, int>.from(state.scores),
    'decisiveRounds': state.decisiveRounds,
    'totalRoundsPlayed': state.totalRoundsPlayed,
    'currentQuestionId': state.currentQuestion?.id,
    'winnerId': state.winnerId,
    'endedBy': state.endedBy,
    'usedAnswerIds': usedList,
    'remainingNearMisses': Map<String, int>.from(state.remainingNearMisses),
    'attemptsCount': state.currentRoundAttempts.length,
    'deadlineMs': state.deadlineMs,
  };
}

List<Map<String, dynamic>> _buildEngineScenarios() {
  final q1 = _makeQuestion(
    id: 'q1',
    categoryId: 'c1',
    title: 'Araba Markaları',
    acceptableAnswers: {
      'Audi': ['audi', 'aude'],
      'BMW': ['bmw'],
      'Mercedes': ['mercedes', 'merco'],
      'Toyota': ['toyota'],
      'Honda': ['honda'],
      'Ford': ['ford'],
    },
  );

  final q2 = _makeQuestion(
    id: 'q2',
    categoryId: 'c2',
    title: 'Meyveler',
    acceptableAnswers: {
      'Elma': ['elma'],
      'Armut': ['armut'],
      'Muz': ['muz'],
      'Çilek': ['cilek'],
      'Portakal': ['portakal'],
      'Karpuz': ['karpuz'],
    },
  );

  final q3 = _makeQuestion(
    id: 'q3',
    categoryId: 'c3',
    title: 'Başkentler',
    acceptableAnswers: {
      'Ankara': ['ankara'],
      'Paris': ['paris'],
      'Berlin': ['berlin'],
      'Roma': ['roma'],
      'Madrid': ['madrid'],
      'Tokyo': ['tokyo'],
    },
  );

  final qSmall = _makeQuestion(
    id: 'q_small',
    categoryId: 'c_small',
    title: 'İki Seçenek',
    acceptableAnswers: {
      'Evet': ['evet'],
      'Hayır': ['hayir'],
    },
  );

  final questionsPool = [q1, q2, q3, qSmall];

  // Helper builder that runs steps on MatchEngine and accumulates JSON
  Map<String, dynamic> runScenario({
    required String id,
    required String name,
    required String description,
    required MatchConfig config,
    required List<String> playerIds,
    required List<String> questionOrder,
    required int initialNowMs,
    required List<(String, Map<String, dynamic>)> stepPlan,
  }) {
    final rng = math.Random(42);
    var engineRes = MatchEngine.start(
      config: config,
      playerIds: playerIds,
      questions: questionsPool,
      random: rng,
      nowMs: initialNowMs,
      questionOrder: questionOrder,
    );
    var state = engineRes.state;

    final stepsJson = <Map<String, dynamic>>[];

    for (int stepIdx = 0; stepIdx < stepPlan.length; stepIdx++) {
      final (action, payload) = stepPlan[stepIdx];
      List<MatchEvent> events;

      switch (action) {
        case 'submit':
          final playerId = payload['playerId'] as String;
          final rawInput = payload['rawInput'] as String;
          final nowMs = payload['nowMs'] as int;
          engineRes = MatchEngine.submit(
            state: state,
            playerId: playerId,
            rawInput: rawInput,
            nowMs: nowMs,
            questionsPool: questionsPool,
            random: rng,
          );
          state = engineRes.state;
          events = engineRes.events;

        case 'tick':
          final nowMs = payload['nowMs'] as int;
          engineRes = MatchEngine.checkTimeout(
            state: state,
            nowMs: nowMs,
          );
          state = engineRes.state;
          events = engineRes.events;

        case 'forfeit':
          final playerId = payload['playerId'] as String;
          final nowMs = payload['nowMs'] as int;
          engineRes = MatchEngine.forfeit(
            state: state,
            playerId: playerId,
            nowMs: nowMs,
          );
          state = engineRes.state;
          events = engineRes.events;

        case 'startNextRound':
          final nowMs = payload['nowMs'] as int;
          engineRes = MatchEngine.startNextRound(
            state: state,
            questions: questionsPool,
            random: rng,
            nowMs: nowMs,
            questionOrder: questionOrder,
          );
          state = engineRes.state;
          events = engineRes.events;

        default:
          throw ArgumentError('Unknown action: $action');
      }

      stepsJson.add({
        'stepIndex': stepIdx,
        'action': action,
        'payload': payload,
        'expectedEvents': events.map(_eventToJson).toList(),
        'expectedStateSnapshot': _stateSnapshot(state),
      });
    }

    return {
      'id': id,
      'name': name,
      'description': description,
      'config': {
        'roundsToWin': config.roundsToWin,
        'answerSeconds': config.answerSeconds,
        'graceMs': config.graceMs,
        'nearMissPerRound': config.nearMissPerRound,
        'minAnswersPerQuestion': config.minAnswersPerQuestion,
        'minSubmitIntervalMs': config.minSubmitIntervalMs,
        'maxAttemptsPerTurn': config.maxAttemptsPerTurn,
      },
      'playerIds': playerIds,
      'questionOrder': questionOrder,
      'initialNowMs': initialNowMs,
      'initialStateSnapshot': _stateSnapshot(
        MatchEngine.start(
          config: config,
          playerIds: playerIds,
          questions: questionsPool,
          random: math.Random(42),
          nowMs: initialNowMs,
          questionOrder: questionOrder,
        ).state,
      ),
      'steps': stepsJson,
    };
  }

  const stdConfig = MatchConfig(
    roundsToWin: 2,
    answerSeconds: 15,
    graceMs: 0,
    nearMissPerRound: 1,
    minSubmitIntervalMs: 600,
    maxAttemptsPerTurn: 25,
  );

  final scenarios = <Map<String, dynamic>>[];

  // 1. 2-0 Clean Win p1
  scenarios.add(runScenario(
    id: 'scen_01_clean_win_p1',
    name: '2-0 Clean Win (P1 wins)',
    description: 'P1 wins round 1 by opponent timeout, wins round 2, match finishes 2-0.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1', 'q2', 'q3'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'audi', 'nowMs': 3000}),
      ('tick', {'nowMs': 18001}), // p2 timeout -> RoundWon(p1, timeout), roundEnded
      ('startNextRound', {'nowMs': 20000}),
      ('submit', {'playerId': 'p2', 'rawInput': 'elma', 'nowMs': 22000}),
      ('submit', {'playerId': 'p1', 'rawInput': 'armut', 'nowMs': 25000}),
      ('tick', {'nowMs': 40001}), // p2 timeout -> RoundWon(p1, timeout), MatchFinished(p1, 'normal')
    ],
  ));

  // 2. 0-2 Clean Win p2
  scenarios.add(runScenario(
    id: 'scen_02_clean_win_p2',
    name: '0-2 Clean Win (P2 wins)',
    description: 'P2 wins both rounds by P1 timeout, match finishes 0-2.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1', 'q2'],
    initialNowMs: 1000,
    stepPlan: [
      ('tick', {'nowMs': 16001}), // p1 starter timeout -> RoundWon(p2, timeout), roundEnded
      ('startNextRound', {'nowMs': 18000}),
      ('submit', {'playerId': 'p2', 'rawInput': 'elma', 'nowMs': 20000}),
      ('tick', {'nowMs': 35001}), // p1 timeout -> RoundWon(p2, timeout), MatchFinished(p2, 'normal')
    ],
  ));

  // 3. 2-1 Contested Match
  scenarios.add(runScenario(
    id: 'scen_03_contested_match_2_1',
    name: '2-1 Contested Match',
    description: 'P1 wins round 1, P2 wins round 2, P1 wins round 3 (decider).',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1', 'q2', 'q3'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'audi', 'nowMs': 2000}),
      ('tick', {'nowMs': 17001}), // p2 timeout -> p1 wins (1-0)
      ('startNextRound', {'nowMs': 19000}),
      ('submit', {'playerId': 'p2', 'rawInput': 'elma', 'nowMs': 21000}),
      ('tick', {'nowMs': 36001}), // p1 timeout -> p2 wins (1-1)
      ('startNextRound', {'nowMs': 38000}),
      ('submit', {'playerId': 'p1', 'rawInput': 'ankara', 'nowMs': 40000}),
      ('tick', {'nowMs': 55001}), // p2 timeout -> p1 wins (2-1), MatchFinished(p1)
    ],
  ));

  // 4. Consecutive Exhausted Draws
  scenarios.add(runScenario(
    id: 'scen_04_consecutive_exhausted_draws',
    name: 'Consecutive Exhausted Draws',
    description: 'Rounds draw when all question answers are exhausted.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q_small', 'q_small', 'q_small'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'evet', 'nowMs': 2000}),
      ('submit', {'playerId': 'p2', 'rawInput': 'hayir', 'nowMs': 3000}), // exhausted -> RoundDrawn
      ('startNextRound', {'nowMs': 5000}),
      ('submit', {'playerId': 'p2', 'rawInput': 'evet', 'nowMs': 6000}),
      ('submit', {'playerId': 'p1', 'rawInput': 'hayir', 'nowMs': 7000}), // exhausted -> RoundDrawn
    ],
  ));

  // 5. 1-1 and 3rd Round Draw
  scenarios.add(runScenario(
    id: 'scen_05_one_one_and_third_round_draw',
    name: '1-1 and 3rd Round Draw',
    description: 'Score is 1-1, round 3 draws due to exhausted answers; match continues.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1', 'q2', 'q_small', 'q3'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'bmw', 'nowMs': 2000}),
      ('tick', {'nowMs': 17001}), // p1 wins (1-0)
      ('startNextRound', {'nowMs': 19000}),
      ('submit', {'playerId': 'p2', 'rawInput': 'elma', 'nowMs': 21000}),
      ('tick', {'nowMs': 36001}), // p2 wins (1-1)
      ('startNextRound', {'nowMs': 38000}),
      ('submit', {'playerId': 'p1', 'rawInput': 'evet', 'nowMs': 39000}),
      ('submit', {'playerId': 'p2', 'rawInput': 'hayir', 'nowMs': 40000}), // round 3 drawn!
    ],
  ));

  // 6. Timeout Round End Starter
  scenarios.add(runScenario(
    id: 'scen_06_timeout_starter',
    name: 'Timeout Round End Starter',
    description: 'Starter P1 makes no move and times out; P2 wins round.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('tick', {'nowMs': 16001}), // timeout starter p1 -> RoundWon(p2, timeout)
    ],
  ));

  // 7. Timeout Round End Non-Starter
  scenarios.add(runScenario(
    id: 'scen_07_timeout_non_starter',
    name: 'Timeout Round End Non-Starter',
    description: 'P1 answers correctly, P2 non-starter times out; P1 wins round.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'audi', 'nowMs': 2000}),
      ('tick', {'nowMs': 17001}), // timeout non-starter p2 -> RoundWon(p1, timeout)
    ],
  ));

  // 8. Dual Timeout Across Rounds
  scenarios.add(runScenario(
    id: 'scen_08_dual_timeout_across_rounds',
    name: 'Dual Timeout Across Rounds',
    description: 'P2 times out in round 1; P1 times out in round 2.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1', 'q2'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'audi', 'nowMs': 2000}),
      ('tick', {'nowMs': 17001}), // P2 timeout -> p1 wins (1-0)
      ('startNextRound', {'nowMs': 19000}),
      ('tick', {'nowMs': 34001}), // P2 starter times out -> p1 wins (2-0), MatchFinished(p1)
    ],
  ));

  // 9. All 6 Answers Exhausted Instant Draw
  scenarios.add(runScenario(
    id: 'scen_09_all_answers_exhausted_instant_draw',
    name: 'All Answers Exhausted Instant Draw',
    description: 'Both players guess all 6 answers of q1; round immediately draws.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'audi', 'nowMs': 2000}),
      ('submit', {'playerId': 'p2', 'rawInput': 'bmw', 'nowMs': 3000}),
      ('submit', {'playerId': 'p1', 'rawInput': 'mercedes', 'nowMs': 4000}),
      ('submit', {'playerId': 'p2', 'rawInput': 'toyota', 'nowMs': 5000}),
      ('submit', {'playerId': 'p1', 'rawInput': 'honda', 'nowMs': 6000}),
      ('submit', {'playerId': 'p2', 'rawInput': 'ford', 'nowMs': 7000}), // 6th answer -> RoundDrawn(exhausted)
    ],
  ));

  // 10. Forfeit in Active Round
  scenarios.add(runScenario(
    id: 'scen_10_forfeit_in_active_round',
    name: 'Forfeit in Active Round',
    description: 'P1 leaves during active round; P2 wins match immediately.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('forfeit', {'playerId': 'p1', 'nowMs': 5000}),
    ],
  ));

  // 11. Forfeit Between Rounds
  scenarios.add(runScenario(
    id: 'scen_11_forfeit_between_rounds',
    name: 'Forfeit Between Rounds',
    description: 'P2 forfeits during roundEnded phase; P1 wins match.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1', 'q2'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'audi', 'nowMs': 2000}),
      ('tick', {'nowMs': 17001}), // round 1 ends
      ('forfeit', {'playerId': 'p2', 'nowMs': 18000}), // forfeit in roundEnded -> MatchFinished(p1, 'forfeit')
    ],
  ));

  // 12. Forfeit After Match Finished
  scenarios.add(runScenario(
    id: 'scen_12_forfeit_after_match_finished',
    name: 'Forfeit After Match Finished',
    description: 'Calling forfeit after match is already finished is ignored.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('forfeit', {'playerId': 'p1', 'nowMs': 3000}),
      ('forfeit', {'playerId': 'p2', 'nowMs': 4000}), // ignored('already_finished')
    ],
  ));

  // 13. Forfeit Freezes Score
  scenarios.add(runScenario(
    id: 'scen_13_forfeit_freezes_score',
    name: 'Forfeit Freezes Score',
    description: 'P1 led 1-0 in round 1, then P1 forfeits in round 2; score freezes at 1-0, P2 wins.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1', 'q2'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'audi', 'nowMs': 2000}),
      ('tick', {'nowMs': 17001}), // p1 wins round 1 (1-0)
      ('startNextRound', {'nowMs': 19000}),
      ('forfeit', {'playerId': 'p1', 'nowMs': 21000}), // p1 forfeits -> p2 wins match, scores stay 1-0
    ],
  ));

  // 14. Double Forfeit
  scenarios.add(runScenario(
    id: 'scen_14_double_forfeit',
    name: 'Double Forfeit',
    description: 'Two consecutive forfeit calls on the same tick; second is ignored.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('forfeit', {'playerId': 'p1', 'nowMs': 5000}),
      ('forfeit', {'playerId': 'p2', 'nowMs': 5000}),
    ],
  ));

  // 15. Near Miss Quota Depleted
  scenarios.add(runScenario(
    id: 'scen_15_near_miss_quota_depleted',
    name: 'Near Miss Quota Depletion',
    description: 'P1 uses 1 near miss (quota 1); next near miss yields WrongAnswer with hintShown=false.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'aude', 'nowMs': 2000}), // NearMiss(p1), quota drops to 0
      ('submit', {'playerId': 'p1', 'rawInput': 'bmwx', 'nowMs': 3000}), // WrongAnswer(p1), isClose=true, hintShown=false
    ],
  ));

  // 16. Near Miss Hidden From Opponent
  scenarios.add(runScenario(
    id: 'scen_16_near_miss_hidden_from_opponent',
    name: 'Near Miss Hidden From Opponent',
    description: 'Near miss attempts are hidden from opponent in visibleAttempts.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'aude', 'nowMs': 2000}), // NearMiss event
    ],
  ));

  // 17. Turn Alternation on Correct Answer
  scenarios.add(runScenario(
    id: 'scen_17_turn_alternation_correct_answer',
    name: 'Turn Alternation on Correct Answer',
    description: 'P1 answers correctly; turn passes to P2 and deadline resets to nowMs + 15s.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'audi', 'nowMs': 4000}),
    ],
  ));

  // 18. Wrong Answer Does Not Pass Turn
  scenarios.add(runScenario(
    id: 'scen_18_wrong_answer_no_turn_change',
    name: 'Wrong Answer Keeps Turn',
    description: 'Wrong answer emits WrongAnswer event, turn stays with current player, deadline unchanged.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'portakal', 'nowMs': 3000}),
    ],
  ));

  // 19. Empty Answer Rejected
  scenarios.add(runScenario(
    id: 'scen_19_empty_answer_rejected',
    name: 'Empty Answer Rejected',
    description: 'Empty or whitespace input emits Ignored("empty_input"), turn does not change.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': '   ', 'nowMs': 2000}),
      ('submit', {'playerId': 'p1', 'rawInput': '', 'nowMs': 3000}),
    ],
  ));

  // 20. Repeated Answer Rejected
  scenarios.add(runScenario(
    id: 'scen_20_repeated_answer_rejected',
    name: 'Repeated Answer Rejected',
    description: 'Previously accepted answer emits AlreadySaid event; turn does not change.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'audi', 'nowMs': 2000}),
      ('submit', {'playerId': 'p2', 'rawInput': 'audi', 'nowMs': 3000}), // AlreadySaid
    ],
  ));

  // 21. Round Starter Alternation
  scenarios.add(runScenario(
    id: 'scen_21_round_starter_alternation',
    name: 'Round Starter Alternation',
    description: 'Round 1 starter is P1 (index 0); Round 2 starter is P2 (index 1); Round 3 starter is P1.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1', 'q2', 'q3'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'audi', 'nowMs': 2000}),
      ('tick', {'nowMs': 17001}), // round 1 ends
      ('startNextRound', {'nowMs': 19000}), // round 2 starter is p2
      ('submit', {'playerId': 'p2', 'rawInput': 'elma', 'nowMs': 20000}),
      ('tick', {'nowMs': 35001}), // round 2 ends
      ('startNextRound', {'nowMs': 37000}), // round 3 starter is p1
    ],
  ));

  // 22. Time Bonus Calculation
  scenarios.add(runScenario(
    id: 'scen_22_time_bonus_calculation',
    name: 'Time Bonus Calculation',
    description: 'Remaining seconds bonus calculation from deadlineMs and submit time.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'audi', 'nowMs': 5000}), // 11s left
      ('tick', {'nowMs': 20001}), // p2 times out
    ],
  ));

  // 23. Round Starting Ticks
  scenarios.add(runScenario(
    id: 'scen_23_round_starting_ticks',
    name: 'Round Starting Ticks',
    description: 'Ticks during active round advance time without ending round until deadline.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('tick', {'nowMs': 5000}),
      ('tick', {'nowMs': 10000}),
      ('tick', {'nowMs': 15000}),
      ('tick', {'nowMs': 16000}), // exactly on deadline -> not timed out yet
      ('tick', {'nowMs': 16001}), // past deadline -> timeout
    ],
  ));

  // 24. Round Ending Wait Ticks
  scenarios.add(runScenario(
    id: 'scen_24_round_ending_wait_ticks',
    name: 'Round Ending Wait Ticks',
    description: 'Ticks during roundEnded phase are no-ops; startNextRound initiates next round.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1', 'q2'],
    initialNowMs: 1000,
    stepPlan: [
      ('tick', {'nowMs': 16001}), // round 1 ends
      ('tick', {'nowMs': 17000}), // tick during roundEnded
      ('tick', {'nowMs': 18000}), // tick during roundEnded
      ('startNextRound', {'nowMs': 19000}),
    ],
  ));

  // 25. Rate Limit and Turn Attempts Limit
  scenarios.add(runScenario(
    id: 'scen_25_rate_limit_and_turn_attempts',
    name: 'Rate Limit and Turn Attempts Limit',
    description: 'Submitting too fast (< 600ms) emits tooFast Ignored event.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p1', 'rawInput': 'yanlis1', 'nowMs': 2000}),
      ('submit', {'playerId': 'p1', 'rawInput': 'yanlis2', 'nowMs': 2300}), // diff 300 ms < 600 ms -> Ignored('tooFast')
      ('submit', {'playerId': 'p1', 'rawInput': 'yanlis3', 'nowMs': 3000}), // diff 700 ms >= 600 ms -> WrongAnswer
    ],
  ));

  // 26. Wrong Player Submit Ignored
  scenarios.add(runScenario(
    id: 'scen_26_wrong_player_submit_ignored',
    name: 'Wrong Player Submit Ignored',
    description: 'Submitting when it is not player turn emits not_player_turn Ignored event.',
    config: stdConfig,
    playerIds: ['p1', 'p2'],
    questionOrder: ['q1'],
    initialNowMs: 1000,
    stepPlan: [
      ('submit', {'playerId': 'p2', 'rawInput': 'audi', 'nowMs': 2000}), // it is p1 turn -> Ignored('not_player_turn')
    ],
  ));

  return scenarios;
}
