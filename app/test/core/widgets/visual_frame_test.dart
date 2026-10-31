import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/widgets/avatar_frame_decorator.dart';
import 'package:app/core/widgets/avatar_frame_registry.dart';
import 'package:app/core/widgets/player_avatar.dart';

void main() {
  group('VisualFrameRegistry manifest and math tests', () {
    test('registry is fully consistent with frames_manifest.json', () {
      final manifestFile = File('assets/frames/frames_manifest.json');
      expect(manifestFile.existsSync(), isTrue,
          reason: 'frames_manifest.json must exist in assets/frames/');

      final manifestJson = jsonDecode(manifestFile.readAsStringSync()) as List<dynamic>;
      final manifestMap = <String, Map<String, dynamic>>{};
      for (final item in manifestJson) {
        final map = item as Map<String, dynamic>;
        manifestMap[map['file'] as String] = map;
      }

      // Check each visual frame in registry
      for (final entry in VisualFrameRegistry.definitions.entries) {
        final catalogId = entry.key;
        final def = entry.value;

        expect(catalogId, equals(def.id));
        final fileName = def.assetPath.split('/').last;
        final manifestEntry = manifestMap[fileName];
        expect(manifestEntry, isNotNull,
            reason: 'File $fileName for $catalogId must be in manifest');

        expect(def.innerRatio,
            closeTo((manifestEntry!['innerRatio'] as num).toDouble(), 0.0001));
      }
    });

    test('sizing math for small area (D <= 48 dp) clamps vine and maintains ratio', () {
      // D = 36 (Leaderboard)
      final dimVine36 = VisualFrameRegistry.calculateDimensionsForFrame(
        frameId: 'vine',
        avatarSize: 36.0,
      );
      expect(dimVine36.isClamped, isTrue);
      // 1.3 * 36 = 46.8
      expect(dimVine36.frameSize, closeTo(46.8, 0.01));
      // avatarSize = 46.8 * 0.658 = 30.7944
      expect(dimVine36.avatarSize, closeTo(46.8 * 0.658, 0.01));

      // D = 36 (Silver - innerRatio 0.821 -> 36 / 0.821 = 43.8489 <= 46.8)
      final dimSilver36 = VisualFrameRegistry.calculateDimensionsForFrame(
        frameId: 'silver_engraved',
        avatarSize: 36.0,
      );
      expect(dimSilver36.isClamped, isFalse);
      expect(dimSilver36.frameSize, closeTo(36.0 / 0.821, 0.01));
      expect(dimSilver36.avatarSize, equals(36.0));

      // D = 44 (Home header)
      final dimVine44 = VisualFrameRegistry.calculateDimensionsForFrame(
        frameId: 'vine',
        avatarSize: 44.0,
      );
      expect(dimVine44.isClamped, isTrue);
      // 1.3 * 44 = 57.2
      expect(dimVine44.frameSize, closeTo(57.2, 0.01));
      expect(dimVine44.avatarSize, closeTo(57.2 * 0.658, 0.01));

      final dimBronze44 = VisualFrameRegistry.calculateDimensionsForFrame(
        frameId: 'bronze_engraved',
        avatarSize: 44.0,
      );
      expect(dimBronze44.isClamped, isFalse);
      expect(dimBronze44.frameSize, closeTo(44.0 / 0.821, 0.01));
      expect(dimBronze44.avatarSize, equals(44.0));
    });

    test('sizing math for large area (D > 48 dp) does not clamp', () {
      final testSizes = [72.0, 88.0, 92.0, 104.0];
      final frameIds = [
        'vine',
        'silver_engraved',
        'bronze_engraved',
        'gold_leaf',
      ];

      for (final size in testSizes) {
        for (final frameId in frameIds) {
          final dim = VisualFrameRegistry.calculateDimensionsForFrame(
            frameId: frameId,
            avatarSize: size,
          );
          final def = VisualFrameRegistry.getDefinition(frameId)!;

          expect(dim.isClamped, isFalse);
          expect(dim.avatarSize, equals(size));
          expect(dim.frameSize, closeTo(size / def.innerRatio, 0.01));
        }
      }
    });

    test('calculateDimensions returns fallback for non-visual frames', () {
      final dim = VisualFrameRegistry.calculateDimensionsForFrame(
        frameId: 'classic',
        avatarSize: 44.0,
      );
      expect(dim.isClamped, isFalse);
      expect(dim.avatarSize, equals(44.0));
      expect(dim.frameSize, equals(44.0));
    });
  });

  group('AvatarFrameType and fallback tests', () {
    test('AvatarFrameType.fromId maps new visual IDs and fallback', () {
      expect(AvatarFrameType.fromId('vine'), equals(AvatarFrameType.vine));
      expect(AvatarFrameType.fromId('silver_engraved'),
          equals(AvatarFrameType.silverEngraved));
      expect(AvatarFrameType.fromId('bronze_engraved'),
          equals(AvatarFrameType.bronzeEngraved));
      expect(AvatarFrameType.fromId('gold_leaf'),
          equals(AvatarFrameType.goldLeaf));

      expect(AvatarFrameType.fromId('unknown_fancy_frame'),
          equals(AvatarFrameType.classic));
      expect(AvatarFrameType.fromId(null), equals(AvatarFrameType.classic));
      expect(AvatarFrameType.fromId(''), equals(AvatarFrameType.classic));
    });

    test('AvatarFramePainter falls back to classic for visual frames', () {
      const painter = AvatarFramePainter(
        frameType: AvatarFrameType.vine,
        borderWidth: 3.0,
      );
      expect(painter.frameType, equals(AvatarFrameType.vine));
      // Doesn't throw during paint
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      expect(() => painter.paint(canvas, const Size(44, 44)), returnsNormally);
    });

    testWidgets('PlayerAvatar renders visual frame with Image.asset and overlay',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: PlayerAvatar.selfHome(
                name: 'Arif',
                frame: 'vine',
                size: 44,
              ),
            ),
          ),
        ),
      );

      // Verify PlayerAvatar is rendered
      expect(find.byType(PlayerAvatar), findsOneWidget);
      // Verify Image.asset is present for the overlay
      expect(find.byType(Image), findsOneWidget);

      final imageWidget = tester.widget<Image>(find.byType(Image));
      final imageProvider = imageWidget.image;
      AssetImage? assetImage;
      if (imageProvider is ResizeImage) {
        assetImage = imageProvider.imageProvider as AssetImage;
      } else if (imageProvider is AssetImage) {
        assetImage = imageProvider;
      }
      expect(assetImage?.assetName, equals('assets/frames/frame_vine.png'));
      expect(imageWidget.filterQuality, equals(FilterQuality.medium));
      expect(imageWidget.gaplessPlayback, isTrue);
    });

    testWidgets('PlayerAvatar falls back to classic painter when frame is unknown',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: PlayerAvatar.selfHome(
                name: 'Arif',
                frame: 'non_existent_future_frame',
                size: 44,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(PlayerAvatar), findsOneWidget);
      // Unknown frame is not visual, so no Image overlay
      expect(find.byType(Image), findsNothing);
      // CustomPaint is used for classic
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}

