import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/online/domain/models/online_messages.dart';
import 'package:app/features/profile/domain/energy_state.dart';
import 'package:app/features/store/data/store_api_client.dart';

Map<String, dynamic> _loadEnergyContractJson() {
  final candidates = [
    '../shared/test-vectors/energy_contract.json',
    'shared/test-vectors/energy_contract.json',
    '../../shared/test-vectors/energy_contract.json',
  ];

  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
  }

  throw StateError('shared/test-vectors/energy_contract.json bulunamadı');
}

void main() {
  group('Shared Energy Contract Vectors Compliance (Flutter Client)', () {
    late Map<String, dynamic> vectors;

    setUpAll(() {
      vectors = _loadEnergyContractJson();
    });

    test('get_me_energy_enabled vektörünü hatasız ayrıştırır ve modeller', () {
      final data = vectors['get_me_energy_enabled'] as Map<String, dynamic>;
      final serverNowMs = (data['serverNowMs'] as num).toInt();
      final energyJson = data['energy'] as Map<String, dynamic>;

      expect(serverNowMs, 1729555200000);

      final energy = EnergyState.fromJson(energyJson);
      expect(energy.enabled, isTrue);
      expect(energy.current, 3);
      expect(energy.max, 5);
      expect(energy.nextEnergyAtMs, 1729556400000);
      expect(energy.regenSeconds, 1200);
      expect(energy.packs.length, 2);

      final p1 = energy.packs[0];
      expect(p1.id, 'one');
      expect(p1.cost, 20);
      expect(p1.energy, 1);

      final p2 = energy.packs[1];
      expect(p2.id, 'full');
      expect(p2.cost, 80);
      expect(p2.energy, 5);
    });

    test('get_me_energy_disabled vektörünü hatasız ayrıştırır (packs boş)', () {
      final data = vectors['get_me_energy_disabled'] as Map<String, dynamic>;
      final energyJson = data['energy'] as Map<String, dynamic>;

      final energy = EnergyState.fromJson(energyJson);
      expect(energy.enabled, isFalse);
      expect(energy.current, 5);
      expect(energy.max, 5);
      expect(energy.nextEnergyAtMs, isNull);
      expect(energy.packs, isEmpty);
    });

    test(
      'post_store_energy.response_200 başarılı satın alma vektörünü ayrıştırır',
      () {
        final postData = vectors['post_store_energy'] as Map<String, dynamic>;
        final res200 = postData['response_200'] as Map<String, dynamic>;
        final body = res200['body'] as Map<String, dynamic>;

        expect(res200['status'], 200);
        expect(body['success'], isTrue);
        expect(body['pack'], 'one');
        expect(body['coins'], 180);
        expect(body['energy'], 4);
        expect(body['max'], 5);
        expect(body['nextEnergyAtMs'], 1729556400000);
        expect(body['serverNowMs'], 1729555200000);

        final successResult = StorePurchaseEnergySuccess(
          coins: (body['coins'] as num).toInt(),
          energy: (body['energy'] as num).toInt(),
          max: (body['max'] as num).toInt(),
          nextEnergyAtMs: (body['nextEnergyAtMs'] as num?)?.toInt(),
          serverNowMs: (body['serverNowMs'] as num).toInt(),
          pack: body['pack'] as String,
        );

        expect(successResult.coins, 180);
        expect(successResult.energy, 4);
      },
    );

    test(
      'matchmaker_no_energy vektörü 1008 ve code=no_energy mesajını doğrular',
      () {
        final noEnergy =
            vectors['matchmaker_no_energy'] as Map<String, dynamic>;
        expect(noEnergy['status'], 1008);
        final msg = noEnergy['message'] as Map<String, dynamic>;
        expect(msg['t'], 'error');
        expect(msg['code'], 'no_energy');
        expect(msg['message'], 'Enerjin bitti');
      },
    );

    test('matchmaker_matched_with_energy vektörünü hatasız ayrıştırır', () {
      final matchedData =
          vectors['matchmaker_matched_with_energy'] as Map<String, dynamic>;
      final msgJson = matchedData['message'] as Map<String, dynamic>;
      final parsed = parseServerMessage(jsonEncode(msgJson));

      expect(parsed, isA<MatchedServerMessage>());
      final matched = parsed as MatchedServerMessage;
      expect(matched.matchId, 'match_12345');
      expect(matched.opponentName, 'Ahmet');
      expect(matched.opponentFrame, 'gold');
      expect(matched.serverNowMs, 1729555200000);
      expect(matched.energy, isNotNull);
      expect(matched.energy!.current, 4);
      expect(matched.energy!.max, 5);
      expect(matched.energy!.nextEnergyAtMs, 1729556400000);
    });

    test('matchmaker_matched_without_energy vektörünü ve geriye dönük uyumluluğu doğrular', () {
      final matchedData =
          vectors['matchmaker_matched_without_energy'] as Map<String, dynamic>;
      final msgJson = matchedData['message'] as Map<String, dynamic>;
      final parsed = parseServerMessage(jsonEncode(msgJson));

      expect(parsed, isA<MatchedServerMessage>());
      final matched = parsed as MatchedServerMessage;
      expect(matched.matchId, 'match_67890');
      expect(matched.opponentName, 'Mehmet');
      expect(matched.opponentFrame, 'classic');
      expect(matched.energy, isNull);
      expect(matched.serverNowMs, isNull);

      // Bilinmeyen ekstra alanlar eklense bile çökmez
      final withUnknown = Map<String, dynamic>.from(msgJson);
      withUnknown['future_unknown_field'] = 'extra';
      final parsedUnknown = parseServerMessage(jsonEncode(withUnknown));
      expect(parsedUnknown, isA<MatchedServerMessage>());
    });
  });
}
