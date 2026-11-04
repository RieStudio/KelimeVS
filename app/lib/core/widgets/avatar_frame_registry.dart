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

  /// Görsel çerçeveler için azami taşma oranı (en geniş çerçeve olan Sarmaşık/vine baz alınarak: ~%23.75 her kenar)
  static const double maxFrameOverflowRatio = 0.2375;

  /// Görsel çerçeveler için azami ölçek çarpanı (1 / 0.678 ~= 1.475)
  static const double maxFrameScaleMultiplier = 1.475;

  /// Senkron kayıt tablosu: Katalog Kimliği -> Çerçeve Tanımı
  static const Map<String, VisualFrameDefinition> definitions = {
    'vine': VisualFrameDefinition(
      id: 'vine',
      assetPath: 'assets/frames/frame_vine.png',
      innerRatio: 0.678,
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
    'emerald': VisualFrameDefinition(
      id: 'emerald',
      assetPath: 'assets/frames/frame_emerald.png',
      innerRatio: 0.809,
      fileName: 'frame_emerald.png',
    ),
    'sakura': VisualFrameDefinition(
      id: 'sakura',
      assetPath: 'assets/frames/frame_sakura.png',
      innerRatio: 0.693,
      fileName: 'frame_sakura.png',
    ),
    'ice': VisualFrameDefinition(
      id: 'ice',
      assetPath: 'assets/frames/frame_ice.png',
      innerRatio: 0.725,
      fileName: 'frame_ice.png',
    ),
    'gear': VisualFrameDefinition(
      id: 'gear',
      assetPath: 'assets/frames/frame_gear.png',
      innerRatio: 0.797,
      fileName: 'frame_gear.png',
    ),
    'nazar': VisualFrameDefinition(
      id: 'nazar',
      assetPath: 'assets/frames/frame_nazar.png',
      innerRatio: 0.8,
      fileName: 'frame_nazar.png',
    ),
  };

  static VisualFrameDefinition? getDefinition(String? frameId) {
    if (frameId == null) return null;
    return definitions[frameId.trim().toLowerCase()];
  }

  static bool isVisualFrame(String? frameId) {
    return getDefinition(frameId) != null;
  }

  /// Verilen avatar boyutu ve çerçeve kimliği için tek taraflı taşma (overflow) miktarını döner.
  /// Çerçevesiz (classic/null) ise 0.0 döner.
  static double getFrameOverflow({
    required double avatarSize,
    required String? frameId,
  }) {
    final def = getDefinition(frameId);
    if (def == null) return 0.0;
    final dims = calculateDimensions(
      baseAvatarSize: avatarSize,
      innerRatio: def.innerRatio,
    );
    return (dims.frameSize - avatarSize) / 2.0;
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

  /// Verilen avatar boyutu için en geniş görsel çerçevenin (Sarmaşık/vine) düzen boyutunu döner.
  static double maxFrameSizeFor(double avatarSize) {
    final vineDef = definitions['vine'];
    if (vineDef == null) return avatarSize;
    return calculateDimensions(
      baseAvatarSize: avatarSize,
      innerRatio: vineDef.innerRatio,
    ).frameSize;
  }

  /// İlk kareden sonra arka planda görsel çerçeveleri önbelleğe alır.
  static void precacheFrames(BuildContext context) {
    for (final def in definitions.values) {
      precacheImage(AssetImage(def.assetPath), context);
    }
  }
}
