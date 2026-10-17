import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/strings/app_strings.dart';
import 'package:app/core/widgets/connection_banner.dart';
import 'package:app/features/game/application/match_ui_state.dart';

void main() {
  Widget buildTestWidget({
    required ConnectionStatus status,
    bool opponentConnected = true,
    Duration debounceDuration = const Duration(milliseconds: 700),
    Duration fadeDuration = const Duration(milliseconds: 200),
    Duration pillDuration = const Duration(milliseconds: 1500),
    bool disableAnimations = false,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: ConnectionBanner(
            status: status,
            opponentConnected: opponentConnected,
            debounceDuration: debounceDuration,
            fadeDuration: fadeDuration,
            pillDuration: pillDuration,
          ),
        ),
      ),
    );
  }

  group('ConnectionBanner Widget Tests', () {
    testWidgets(
      'Kopma 700 ms\'den kısa sürerse (örn. 400 ms) şerit HİÇ görünmez ve titreme olmaz',
      (tester) async {
        var currentStatus = ConnectionStatus.connected;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(status: currentStatus);
            },
          ),
        );

        // Başlangıçta görünmez
        expect(find.text(AppStrings.connectionReconnecting), findsNothing);
        expect(find.text(AppStrings.connectionRestored), findsNothing);

        // 1. Durum reconnecting'e geçer
        currentStatus = ConnectionStatus.reconnecting;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(status: currentStatus);
            },
          ),
        );

        // 400 ms sonra henüz debounce dolmadı, şerit görünmemeli
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(AppStrings.connectionReconnecting), findsNothing);

        // 2. 400 ms'de bağlantı geri geldi
        currentStatus = ConnectionStatus.connected;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(status: currentStatus);
            },
          ),
        );

        // Bir süre daha ilerlet; şerit ve "Bağlandı" hapı hiç çıkmamış olmalı
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text(AppStrings.connectionReconnecting), findsNothing);
        expect(find.text(AppStrings.connectionRestored), findsNothing);
      },
    );

    testWidgets(
      'Kopma 700 ms\'den uzun sürerse şerit görünür; bağlanınca 1.5 sn "Bağlandı" hapı çıkıp kaybolur',
      (tester) async {
        var currentStatus = ConnectionStatus.connected;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(status: currentStatus);
            },
          ),
        );

        // 1. Kopma başlar
        currentStatus = ConnectionStatus.reconnecting;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(status: currentStatus);
            },
          ),
        );

        // 699 ms'de hala yok
        await tester.pump(const Duration(milliseconds: 699));
        expect(find.text(AppStrings.connectionReconnecting), findsNothing);

        // 701 ms'de (debounce doldu) şerit görünür
        await tester.pump(const Duration(milliseconds: 2));
        expect(find.text(AppStrings.connectionReconnecting), findsOneWidget);

        // 2. Bağlantı geri gelir
        currentStatus = ConnectionStatus.connected;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(status: currentStatus);
            },
          ),
        );

        // 200 ms içinde şerit solup yerini "Bağlandı" hapına bırakır
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(AppStrings.connectionRestored), findsOneWidget);

        // 1400 ms sonra "Bağlandı" hapı hala ekranda
        await tester.pump(const Duration(milliseconds: 1400));
        expect(find.text(AppStrings.connectionRestored), findsOneWidget);

        // Toplam 1.5 sn dolunca (100 ms + fade 200 ms) hap kaybolur
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(AppStrings.connectionRestored), findsNothing);
        expect(find.text(AppStrings.connectionReconnecting), findsNothing);
      },
    );

    testWidgets(
      'disableAnimations açıkken geçişler animasyonsuz ve anında yapılır',
      (tester) async {
        var currentStatus = ConnectionStatus.connected;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(
                status: currentStatus,
                disableAnimations: true,
              );
            },
          ),
        );

        currentStatus = ConnectionStatus.reconnecting;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(
                status: currentStatus,
                disableAnimations: true,
              );
            },
          ),
        );

        // 700 ms debounce dolunca şerit anında görünür
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text(AppStrings.connectionReconnecting), findsOneWidget);

        currentStatus = ConnectionStatus.connected;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(
                status: currentStatus,
                disableAnimations: true,
              );
            },
          ),
        );

        // Animasyonsuz anında hap görünür
        await tester.pump();
        expect(find.text(AppStrings.connectionRestored), findsOneWidget);

        // 1.5 sn dolunca anında kaybolur
        await tester.pump(const Duration(milliseconds: 1500));
        expect(find.text(AppStrings.connectionRestored), findsNothing);
      },
    );

    testWidgets(
      'Kalıcı kopma durumunda (permanentDisconnected) şerit hemen kapanır',
      (tester) async {
        var currentStatus = ConnectionStatus.reconnecting;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(status: currentStatus);
            },
          ),
        );

        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text(AppStrings.connectionReconnecting), findsOneWidget);

        currentStatus = ConnectionStatus.permanentDisconnected;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(status: currentStatus);
            },
          ),
        );

        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(AppStrings.connectionReconnecting), findsNothing);
        expect(find.text(AppStrings.connectionRestored), findsNothing);
      },
    );

    testWidgets(
      'Rakip bağlantısı kopunca (opponentConnected: false) şerit "Rakibin bağlantısı koptu" ile görünür',
      (tester) async {
        var opponentConnected = true;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(
                status: ConnectionStatus.connected,
                opponentConnected: opponentConnected,
              );
            },
          ),
        );

        expect(find.text(AppStrings.opponentConnectionLost), findsNothing);

        // Rakip koptu
        opponentConnected = false;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(
                status: ConnectionStatus.connected,
                opponentConnected: opponentConnected,
              );
            },
          ),
        );

        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(AppStrings.opponentConnectionLost), findsOneWidget);
        expect(find.text(AppStrings.connectionReconnecting), findsNothing);
      },
    );

    testWidgets(
      'Rakip geri dönünce şerit kaybolur ve "Bağlandı" hapı GÖSTERİLMEZ',
      (tester) async {
        var opponentConnected = false;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(
                status: ConnectionStatus.connected,
                opponentConnected: opponentConnected,
              );
            },
          ),
        );

        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text(AppStrings.opponentConnectionLost), findsOneWidget);

        // Rakip geri döndü
        opponentConnected = true;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(
                status: ConnectionStatus.connected,
                opponentConnected: opponentConnected,
              );
            },
          ),
        );

        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text(AppStrings.opponentConnectionLost), findsNothing);
        // "Bağlandı" hapı çıkmamalı
        expect(find.text(AppStrings.connectionRestored), findsNothing);
      },
    );

    testWidgets(
      'Kendi bağlantımız da koparsa öncelik bizim bağlantımızdadır, rakip şeridi gizlenir ve sadece bizim şeridimiz gösterilir',
      (tester) async {
        var status = ConnectionStatus.connected;
        var opponentConnected = false;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(
                status: status,
                opponentConnected: opponentConnected,
              );
            },
          ),
        );

        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text(AppStrings.opponentConnectionLost), findsOneWidget);

        // Bizim bağlantımız koptu
        status = ConnectionStatus.reconnecting;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(
                status: status,
                opponentConnected: opponentConnected,
              );
            },
          ),
        );

        // Debounce sırasında rakip şeridi solar ve kaybolur (250 ms), ikisi üst üste binmez
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text(AppStrings.opponentConnectionLost), findsNothing);
        expect(find.text(AppStrings.connectionReconnecting), findsNothing);

        // 700 ms debounce dolunca (kalan 450 ms) sadece kendi reconnection şeridimiz görünür
        await tester.pump(const Duration(milliseconds: 450));
        expect(find.text(AppStrings.connectionReconnecting), findsOneWidget);
        expect(find.text(AppStrings.opponentConnectionLost), findsNothing);
      },
    );

    testWidgets(
      'Kendi bağlantımız geri gelince "Bağlandı" hapından sonra rakip hala kopuksa rakip şeridine dönülür',
      (tester) async {
        var status = ConnectionStatus.reconnecting;
        var opponentConnected = false;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(
                status: status,
                opponentConnected: opponentConnected,
              );
            },
          ),
        );

        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text(AppStrings.connectionReconnecting), findsOneWidget);

        // Bizim bağlantımız geri geldi
        status = ConnectionStatus.connected;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return buildTestWidget(
                status: status,
                opponentConnected: opponentConnected,
              );
            },
          ),
        );

        // 200 ms içinde "Bağlandı" hapı görünür
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text(AppStrings.connectionRestored), findsOneWidget);
        expect(find.text(AppStrings.opponentConnectionLost), findsNothing);

        // 1.5 sn dolunca "Bağlandı" hapı biter ve rakip şeridine dönülür
        await tester.pump(const Duration(milliseconds: 1500));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text(AppStrings.connectionRestored), findsNothing);
        expect(find.text(AppStrings.opponentConnectionLost), findsOneWidget);
      },
    );
  });
}
