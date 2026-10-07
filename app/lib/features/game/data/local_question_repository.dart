// SADECE GELİŞTİRME. Faz 4'te sunucu tabanlı depo ile değiştirilecek ve bu varlık uygulamadan kaldırılacak. Cevap listesi yayın sürümünde istemcide bulunmamalı.

import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import 'question_repository.dart';

/// SADECE GELİŞTİRME. Faz 4'te sunucu tabanlı depo ile değiştirilecek ve bu varlık uygulamadan kaldırılacak. Cevap listesi yayın sürümünde istemcide bulunmamalı.
class LocalQuestionRepository implements QuestionRepository {
  final String assetPath;
  final AssetBundle? bundle;

  const LocalQuestionRepository({
    this.assetPath = 'assets/dev/questions.json',
    this.bundle,
  });

  @override
  Future<List<Question>> loadAll() async {
    final effectiveBundle = bundle ?? rootBundle;
    final jsonString = await effectiveBundle.loadString(assetPath);
    final dynamic decoded = json.decode(jsonString);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Geçersiz soru havuzu JSON biçimi');
    }

    return Question.parseQuestionsPool(decoded);
  }
}

