import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/widgets/avatar_frame_decorator.dart';
import 'package:app/core/widgets/avatar_frame_registry.dart';
import 'package:app/core/widgets/player_avatar.dart';
import 'package:app/gallery/component_gallery.dart';

Future<double> _measureHoleRatioFromAssetPng(String assetPath) async {
  final file = File(assetPath);
  expect(file.existsSync(), isTrue, reason: 'File $assetPath must exist');
  final bytes = await file.readAsBytes();
  final codec = await instantiateImageCodec(bytes);
  final frameInfo = await codec.getNextFrame();
  final image = frameInfo.image;
  final byteData = await image.toByteData(format: ImageByteFormat.rawRgba);
  if (byteData == null) {
    throw StateError('Cannot read raw RGBA bytes for $assetPath');
  }

  final width = image.width;
  final height = image.height;
  final cx = width ~/ 2;
  final cy = height ~/ 2;

  int getAlpha(int x, int y) {
    final offset = (y * width + x) * 4;
    return byteData.getUint8(offset + 3);
  }

  // Ray East (x: cx -> width - 1)
  int eastDist = cx;
  for (int x = cx; x < width; x++) {
    if (getAlpha(x, cy) > 200) {
      eastDist = x - cx;
      break;
    }
  }

  // Ray West (x: cx -> 0)
  int westDist = cx;
  for (int x = cx; x >= 0; x--) {
    if (getAlpha(x, cy) > 200) {
      westDist = cx - x;
      break;
    }
  }

  // Ray South (y: cy -> height - 1)
  int southDist = cy;
  for (int y = cy; y < height; y++) {
    if (getAlpha(cx, y) > 200) {
      southDist = y - cy;
      break;
    }
  }

  // Ray North (y: cy -> 0)
  int northDist = cy;
  for (int y = cy; y >= 0; y--) {
    if (getAlpha(cx, y) > 200) {
      northDist = cy - y;
      break;
    }
  }

  final avgRadius = (eastDist + westDist + southDist + northDist) / 4.0;
  final diameterRatio = (avgRadius * 2.0) / width;
  return diameterRatio;
}

void main() {
  group('VisualFrameRegistry manifest and math tests', () {
    test('registry is fully consistent with frames_manifest.json', () {
      final manifestFile = File('assets/frames/frames_manifest.json');
      expect(manifestFile.existsSync(), isTrue,
          reason: 'frames_manifest.json must exist in assets/frames/');

      final manifestJson =
          jsonDecode(manifestFile.readAsStringSync()) as List<dynamic>;
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
      // avatarSize = 46.8 * 0.678 = 31.7304
      expect(dimVine36.avatarSize, closeTo(46.8 * 0.678, 0.01));

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
      expect(dimVine44.avatarSize, closeTo(57.2 * 0.678, 0.01));

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

      expect(find.byType(PlayerAvatar), findsOneWidget);
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

    testWidgets(
        'PlayerAvatar falls back to classic painter when frame is unknown',
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
      expect(find.byType(Image), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('Asset-independent PNG hole measurement and validation', () {
    final frames = [
      ('vine', 'assets/frames/frame_vine.png'),
      ('silver_engraved', 'assets/frames/frame_silver.png'),
      ('bronze_engraved', 'assets/frames/frame_bronze.png'),
      ('gold_leaf', 'assets/frames/frame_gold.png'),
    ];

    for (final (frameId, assetPath) in frames) {
      test('measured hole ratio from PNG for $frameId matches registry within <= 1%',
          () async {
        final measuredRatio = await _measureHoleRatioFromAssetPng(assetPath);
        final def = VisualFrameRegistry.getDefinition(frameId)!;
        final diff = (measuredRatio - def.innerRatio).abs();

        // Must be within <= 0.01 (1%)
        expect(diff, lessThanOrEqualTo(0.01),
            reason:
                '$frameId: measured $measuredRatio vs registry ${def.innerRatio} diff $diff must be <= 0.01');
      });
    }
  });

  group('Regression test: rendered hole radius vs avatar radius alignment', () {
    final frames = [
      ('vine', 'assets/frames/frame_vine.png'),
      ('silver_engraved', 'assets/frames/frame_silver.png'),
      ('bronze_engraved', 'assets/frames/frame_bronze.png'),
      ('gold_leaf', 'assets/frames/frame_gold.png'),
    ];

    const testSizes = [104.0, 88.0];

    for (final (frameId, assetPath) in frames) {
      for (final size in testSizes) {
        test(
            '$frameId at D=$size: hole radius matches avatar radius (<= 1.5% and <= 1.0 dp)',
            () async {
          final measuredRatio = await _measureHoleRatioFromAssetPng(assetPath);
          final def = VisualFrameRegistry.getDefinition(frameId)!;

          final avatarRadius = size / 2.0;
          // rendered hole radius = (avatarRadius / innerRatio) * measuredRatio
          final renderedHoleRadius =
              (avatarRadius / def.innerRatio) * measuredRatio;
          final radiusDiff = (renderedHoleRadius - avatarRadius).abs();
          final percentageDiff = radiusDiff / avatarRadius;

          expect(percentageDiff, lessThanOrEqualTo(0.015),
              reason:
                  'Relative difference ${(percentageDiff * 100).toStringAsFixed(3)}% must be <= 1.5%');
          expect(radiusDiff, lessThanOrEqualTo(1.0),
              reason:
                  'Absolute difference ${radiusDiff.toStringAsFixed(3)} dp must be <= 1.0 dp');
        });
      }
    }
  });

  group('PlayerAvatar render layout and concentricity (D=104 and D=88)', () {
    final frames = [
      'vine',
      'silver_engraved',
      'bronze_engraved',
      'gold_leaf',
    ];

    const testSizes = [104.0, 88.0];

    for (final frameId in frames) {
      for (final size in testSizes) {
        testWidgets(
            'Render sizes and centering for $frameId at D=$size',
            (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: PlayerAvatar.selfMatch(
                    name: 'A',
                    frame: frameId,
                    size: size,
                  ),
                ),
              ),
            ),
          );

          final avatarFinder = find.byType(PlayerAvatar);
          expect(avatarFinder, findsOneWidget);

          final imageFinder = find.byType(Image);
          expect(imageFinder, findsOneWidget);
          final imageRenderBox =
              tester.renderObject(imageFinder) as RenderBox;
          final imageSize = imageRenderBox.size;
          final imageCenter = imageRenderBox.localToGlobal(
              Offset(imageSize.width / 2, imageSize.height / 2));

          final containerFinder = find.descendant(
            of: avatarFinder,
            matching: find.byType(Container),
          );
          final containerRenderBox =
              tester.renderObject(containerFinder.first) as RenderBox;
          final containerSize = containerRenderBox.size;
          final containerCenter = containerRenderBox.localToGlobal(
              Offset(containerSize.width / 2, containerSize.height / 2));

          final def = VisualFrameRegistry.getDefinition(frameId)!;
          final expectedFrameSize = size / def.innerRatio;

          expect(containerSize.width, equals(size));
          expect(containerSize.height, equals(size));
          expect(imageSize.width, closeTo(expectedFrameSize, 0.01));
          expect(imageSize.height, closeTo(expectedFrameSize, 0.01));
          expect((imageCenter - containerCenter).distance, closeTo(0.0, 0.001));
        });
      }
    }
  });

  group('ComponentGallery debug red ring guide', () {
    testWidgets('toggling switch displays red alignment guide border',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FrameGallerySection(),
            ),
          ),
        ),
      );

      final switchFinder =
          find.byKey(const ValueKey('debug_frame_red_ring_switch'));
      expect(switchFinder, findsOneWidget);

      // Initially, no red guide border container should be drawn
      Finder redBorderFinder() => find.byWidgetPredicate((widget) {
            if (widget is Container && widget.decoration is BoxDecoration) {
              final box = widget.decoration as BoxDecoration;
              if (box.border != null && box.shape == BoxShape.circle) {
                final topBorder = box.border!.top;
                return topBorder.color == Colors.redAccent &&
                    topBorder.width == 1.0;
              }
            }
            return false;
          });

      expect(redBorderFinder(), findsNothing);

      // Toggle switch to ON
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Red guide border should now be visible on all avatar sizes
      expect(redBorderFinder(), findsWidgets);
    });
  });
}
