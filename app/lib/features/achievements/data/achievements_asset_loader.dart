import 'dart:convert';
import 'package:flutter/services.dart';

/// app/assets/achievements/achievements.json içindeki başarım tanımları.
class AchievementAssetDefinition {
  final String id;
  final String category;
  final int threshold;
  final int order;

  const AchievementAssetDefinition({
    required this.id,
    required this.category,
    required this.threshold,
    required this.order,
  });

  factory AchievementAssetDefinition.fromJson(Map<String, dynamic> json) {
    return AchievementAssetDefinition(
      id: json['id'] as String? ?? '',
      category: json['category'] as String? ?? '',
      threshold: (json['threshold'] as num?)?.toInt() ?? 0,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// assets/achievements/achievements.json dosyasını yükleyen yardımcı sınıf.
class AchievementsAssetLoader {
  static const String assetPath = 'assets/achievements/achievements.json';

  final AssetBundle? bundle;

  const AchievementsAssetLoader({this.bundle});

  Future<List<AchievementAssetDefinition>> loadAll() async {
    final b = bundle ?? rootBundle;
    final jsonString = await b.loadString(assetPath);
    return parseJsonString(jsonString);
  }

  static List<AchievementAssetDefinition> parseJsonString(String jsonString) {
    final decoded = jsonDecode(jsonString) as List<dynamic>;
    return decoded
        .map((e) => AchievementAssetDefinition.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
