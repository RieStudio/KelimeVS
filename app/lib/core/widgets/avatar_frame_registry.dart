import 'package:flutter/widgets.dart';

@immutable
class VisualFrameDefinition {
  final String id;
  final String assetPath;
  final double innerRatio;
  final String fileName;

  const VisualFrameDefinition({
    required this.id,
    required this.assetPath,
    required this.innerRatio,
    required this.fileName,
  });
}

/// Avatar görsel çerçeve kayıt tablosu ve boyutlandırma kuralları.
abstract final class VisualFrameRegistry {
  /// Küçük alan kuralı eşiği: D <= 48 dp
  static const double smallAreaThreshold = 48.0;

  /// Küçük alan azami ölçek çarpanı: 1.3 * D
  static const double smallAreaMaxScaleMultiplier = 1.3;

  /// Senkron kayıt tablosu: Katalog Kimliği -> Çerçeve Tanımı
  static const Map<String, VisualFrameDefinition> definitions = {
    'vine': VisualFrameDefinition(
      id: 'vine',
      assetPath: 'assets/frames/frame_vine.png',
      innerRatio: 0.658,
      fileName: 'frame_vine.png',
    ),
    'silver_engraved': VisualFrameDefinition(
      id: 'silver_engraved',
      assetPath: 'assets/frames/frame_silver.png',
      innerRatio: 0.821,
      fileName: 'frame_silver.png',
    ),
    'bronze_engraved': VisualFrameDefinition(
      id: 'bronze_engraved',
      assetPath: 'assets/frames/frame_bronze.png',
      innerRatio: 0.821,
      fileName: 'frame_bronze.png',
    ),
    'gold_leaf': VisualFrameDefinition(
      id: 'gold_leaf',
      assetPath: 'assets/frames/frame_gold.png',
      innerRatio: 0.809,
      fileName: 'frame_gold.png',
    ),
  };

  static VisualFrameDefinition? getDefinition(String? frameId) {
    if (frameId == null) return null;
    return definitions[frameId.trim().toLowerCase()];
  }

  static bool isVisualFrame(String? frameId) {
    return getDefinition(frameId) != null;
  }

  /// Verilen avatar boyutu (baseAvatarSize = D) ve innerRatio için
  /// efektif frameSize ve avatarSize değerlerini hesaplar.
  ///
  /// Kural:
  /// - D <= 48 dp için frameSize en fazla 1.3 * D ile sınırlanır.
  ///   Sınır aşılıyorsa (ör. Sarmaşık):
  ///     frameSize = 1.3 * D
  ///     avatarSize = frameSize * innerRatio (avatar küçülür).
  ///   Sınır aşılmıyorsa (ör. Gümüş/Bronz/Altın Yaprak):
  ///     frameSize = D / innerRatio
  ///     avatarSize = D (avatar küçülmez).
  /// - D > 48 dp için sınır yoktur:
  ///     frameSize = D / innerRatio
  ///     avatarSize = D
  static ({double frameSize, double avatarSize, bool isClamped}) calculateDimensions({
    required double baseAvatarSize,
    required double innerRatio,
  }) {
    final idealFrameSize = baseAvatarSize / innerRatio;

    if (baseAvatarSize <= smallAreaThreshold) {
      final maxFrameSize = baseAvatarSize * smallAreaMaxScaleMultiplier;
      if (idealFrameSize > maxFrameSize) {
        final clampedFrameSize = maxFrameSize;
        final clampedAvatarSize = clampedFrameSize * innerRatio;
        return (
          frameSize: clampedFrameSize,
          avatarSize: clampedAvatarSize,
          isClamped: true,
        );
      }
    }

    return (
      frameSize: idealFrameSize,
      avatarSize: baseAvatarSize,
      isClamped: false,
    );
  }

  /// Belirli bir çerçeve kimliği ve avatar boyutu için boyutları hesaplar.
  static ({double frameSize, double avatarSize, bool isClamped}) calculateDimensionsForFrame({
    required String frameId,
    required double avatarSize,
  }) {
    final def = getDefinition(frameId);
    if (def == null) {
      return (
        frameSize: avatarSize,
        avatarSize: avatarSize,
        isClamped: false,
      );
    }
    return calculateDimensions(
      baseAvatarSize: avatarSize,
      innerRatio: def.innerRatio,
    );
  }

  /// İlk kareden sonra arka planda 4 görseli önbelleğe alır.
  static void precacheFrames(BuildContext context) {
    for (final def in definitions.values) {
      precacheImage(AssetImage(def.assetPath), context);
    }
  }
}
