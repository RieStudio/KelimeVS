import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Uygulama Ekran Yönelimi (App Orientation Lock)', () {
    test('SystemChrome.setPreferredOrientations çağrısının portraitUp ile yapıldığını platform kanalı mock ile doğrular', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          calls.add(methodCall);
          return null;
        },
      );

      await setAppOrientation();

      final orientationCalls = calls.where(
        (call) => call.method == 'SystemChrome.setPreferredOrientations',
      ).toList();

      expect(orientationCalls, hasLength(1));
      expect(
        orientationCalls.first.arguments,
        equals(['DeviceOrientation.portraitUp']),
      );
    });

    test('main.dart içinde runApp öncesinde portraitUp yönelim kilitleme çağrısı yapılmıştır', () {
      final file = File('lib/main.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();

      expect(content.contains('SystemChrome.setPreferredOrientations'), isTrue);
      expect(content.contains('DeviceOrientation.portraitUp'), isTrue);

      final mainStart = content.indexOf('main()');
      expect(mainStart, isNonNegative);
      final mainBody = content.substring(mainStart);

      final ensureIdx = mainBody.indexOf('WidgetsFlutterBinding.ensureInitialized()');
      final orientIdx = mainBody.indexOf('SystemChrome.setPreferredOrientations');
      final runAppIdx = mainBody.indexOf('runApp(');

      expect(ensureIdx, isNonNegative);
      expect(orientIdx, isNonNegative);
      expect(runAppIdx, isNonNegative);

      expect(orientIdx, greaterThan(ensureIdx), reason: 'WidgetsFlutterBinding.ensureInitialized sonrasında çağrılmalı');
      expect(orientIdx, lessThan(runAppIdx), reason: 'runApp öncesinde çağrılmalı');
    });
  });
}
