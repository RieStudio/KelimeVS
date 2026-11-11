import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/strings/app_strings.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/profile/data/public_profile_api_client.dart';
import 'package:app/features/profile/domain/public_profile_model.dart';

class FakeAuthTokenProvider implements AuthTokenProvider {
  final String? token;
  const FakeAuthTokenProvider({this.token = 'test_token'});

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => token;
}

class FakeHttpClient implements HttpClient {
  int statusCode;
  String responseBody;
  bool shouldThrow;

  FakeHttpClient({
    this.statusCode = 200,
    this.responseBody = '{}',
    this.shouldThrow = false,
  });

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (shouldThrow) throw const SocketException('Ağ erişilemiyor');
    return FakeHttpClientRequest(
      statusCode: statusCode,
      responseBody: responseBody,
    );
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    if (shouldThrow) throw const SocketException('Ağ erişilemiyor');
    return FakeHttpClientRequest(
      statusCode: statusCode,
      responseBody: responseBody,
    );
  }

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) async {
    if (shouldThrow) throw const SocketException('Ağ erişilemiyor');
    return FakeHttpClientRequest(
      statusCode: statusCode,
      responseBody: responseBody,
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClientRequest implements HttpClientRequest {
  final int statusCode;
  final String responseBody;

  FakeHttpClientRequest({required this.statusCode, required this.responseBody});

  @override
  final HttpHeaders headers = FakeHttpHeaders();

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async {
    return FakeHttpClientResponse(statusCode: statusCode, body: responseBody);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  FakeHttpClientResponse({required this.statusCode, required this.body});

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  final HttpHeaders headers = FakeHttpHeaders();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHttpHeaders implements HttpHeaders {
  final Map<String, Object> _headers = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('HttpPublicProfileApiClient - getPublicProfile', () {
    test('200 OK yanıtında PublicProfile başarıyla döner', () async {
      final fake = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({
          'uid': 'user_456',
          'nickname': 'Bob',
          'equippedFrame': 'nazar',
          'stats': {
            'played': 20,
            'won': 15,
            'lost': 5,
            'winRate': 75,
          },
          'isGuest': false,
          'isBlocked': false,
          'blockId': null,
        }),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      final profile = await client.getPublicProfile('user_456');

      expect(profile.uid, 'user_456');
      expect(profile.nickname, 'Bob');
      expect(profile.equippedFrame, 'nazar');
      expect(profile.stats.played, 20);
      expect(profile.stats.winRate, 75);
    });

    test('404 Not Found durumunda notFound exception fırlatır', () async {
      final fake = FakeHttpClient(
        statusCode: 404,
        responseBody: jsonEncode({'error': 'not_found'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      expect(
        () => client.getPublicProfile('missing_uid'),
        throwsA(
          isA<PublicProfileException>()
              .having((e) => e.kind, 'kind', PublicProfileErrorKind.notFound)
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', AppStrings.profileNotFound),
        ),
      );
    });

    test('410 Gone (hedef silinmiş) durumunda deleted exception fırlatır',
        () async {
      final fake = FakeHttpClient(
        statusCode: 410,
        responseBody: jsonEncode({'error': 'deleted'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      expect(
        () => client.getPublicProfile('deleted_uid'),
        throwsA(
          isA<PublicProfileException>()
              .having((e) => e.kind, 'kind', PublicProfileErrorKind.deleted)
              .having((e) => e.statusCode, 'statusCode', 410)
              .having((e) => e.message, 'message', AppStrings.profileDeleted),
        ),
      );
    });

    test(
        '410 Gone (oturum sahibi silinmiş - account_deleted) onAccountDeleted çağrılır',
        () async {
      var deletedCalled = false;
      final fake = FakeHttpClient(
        statusCode: 410,
        responseBody: jsonEncode({'error': 'account_deleted'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
        onAccountDeleted: () {
          deletedCalled = true;
        },
      );

      await expectLater(
        () => client.getPublicProfile('some_uid'),
        throwsA(isA<PublicProfileException>()),
      );
      expect(deletedCalled, true);
    });

    test('401 Unauthorized durumunda unauthorized exception fırlatır',
        () async {
      final fake = FakeHttpClient(
        statusCode: 401,
        responseBody: jsonEncode({'error': 'unauthorized'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      expect(
        () => client.getPublicProfile('user_xyz'),
        throwsA(
          isA<PublicProfileException>()
              .having(
                  (e) => e.kind, 'kind', PublicProfileErrorKind.unauthorized)
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('400 Bad Request durumunda invalidUid exception fırlatır', () async {
      final fake = FakeHttpClient(
        statusCode: 400,
        responseBody: jsonEncode({'error': 'invalid_uid'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      expect(
        () => client.getPublicProfile('invalid@uid!'),
        throwsA(
          isA<PublicProfileException>()
              .having((e) => e.kind, 'kind', PublicProfileErrorKind.invalidUid)
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('Ağ hatası durumunda networkOrTimeout exception fırlatır', () async {
      final fake = FakeHttpClient(shouldThrow: true);

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      expect(
        () => client.getPublicProfile('any_uid'),
        throwsA(
          isA<PublicProfileException>().having(
            (e) => e.kind,
            'kind',
            PublicProfileErrorKind.networkOrTimeout,
          ),
        ),
      );
    });
  });

  group('HttpPublicProfileApiClient - blockUser', () {
    test('200 OK yanıtında blockId döner', () async {
      final fake = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({'ok': true, 'blockId': 'blk_777'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      final blockId = await client.blockUser('target_uid');
      expect(blockId, 'blk_777');
    });

    test('400 cannot_block_self durumunda cannotBlockSelf exception fırlatır',
        () async {
      final fake = FakeHttpClient(
        statusCode: 400,
        responseBody: jsonEncode({'error': 'cannot_block_self'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      expect(
        () => client.blockUser('my_own_uid'),
        throwsA(
          isA<PublicProfileException>()
              .having(
                  (e) => e.kind, 'kind', PublicProfileErrorKind.cannotBlockSelf)
              .having((e) => e.message, 'message',
                  AppStrings.profileCannotBlockSelf),
        ),
      );
    });

    test('400 block_limit_reached durumunda blockLimit exception fırlatır',
        () async {
      final fake = FakeHttpClient(
        statusCode: 400,
        responseBody: jsonEncode({'error': 'block_limit_reached'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      expect(
        () => client.blockUser('target_uid'),
        throwsA(
          isA<PublicProfileException>()
              .having((e) => e.kind, 'kind', PublicProfileErrorKind.blockLimit)
              .having(
                  (e) => e.message, 'message', AppStrings.profileBlockLimit),
        ),
      );
    });
  });

  group('HttpPublicProfileApiClient - unblockUser', () {
    test('200 OK yanıtında sessizce tamamlanır', () async {
      final fake = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({'ok': true}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      await expectLater(client.unblockUser('blocked_uid'), completes);
    });

    test('410 durumunda deleted exception fırlatır', () async {
      final fake = FakeHttpClient(
        statusCode: 410,
        responseBody: jsonEncode({'error': 'deleted'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      expect(
        () => client.unblockUser('deleted_uid'),
        throwsA(
          isA<PublicProfileException>()
              .having((e) => e.kind, 'kind', PublicProfileErrorKind.deleted),
        ),
      );
    });
  });

  group('HttpPublicProfileApiClient - reportUser', () {
    test('200 OK yanıtında reportId döner', () async {
      final fake = FakeHttpClient(
        statusCode: 200,
        responseBody: jsonEncode({'ok': true, 'reportId': 'rep_12345'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      final reportId = await client.reportUser('user_bad', 'cheating');
      expect(reportId, 'rep_12345');
    });

    test('409 Conflict durumunda alreadyReported exception fırlatır', () async {
      final fake = FakeHttpClient(
        statusCode: 409,
        responseBody: jsonEncode({'error': 'already_reported'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      expect(
        () => client.reportUser('user_bad', 'other'),
        throwsA(
          isA<PublicProfileException>()
              .having((e) => e.kind, 'kind',
                  PublicProfileErrorKind.alreadyReported)
              .having((e) => e.message, 'message',
                  AppStrings.profileAlreadyReported),
        ),
      );
    });

    test('429 Too Many Requests durumunda dailyLimit exception fırlatır',
        () async {
      final fake = FakeHttpClient(
        statusCode: 429,
        responseBody: jsonEncode({'error': 'daily_limit_exceeded'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      expect(
        () => client.reportUser('user_bad', 'inappropriate_nickname'),
        throwsA(
          isA<PublicProfileException>()
              .having((e) => e.kind, 'kind', PublicProfileErrorKind.dailyLimit)
              .having((e) => e.message, 'message',
                  AppStrings.profileDailyReportLimit),
        ),
      );
    });

    test('400 cannot_report_self durumunda cannotReportSelf exception fırlatır',
        () async {
      final fake = FakeHttpClient(
        statusCode: 400,
        responseBody: jsonEncode({'error': 'cannot_report_self'}),
      );

      final client = HttpPublicProfileApiClient(
        authTokenProvider: const FakeAuthTokenProvider(),
        clientFactory: () => fake,
      );

      expect(
        () => client.reportUser('my_uid', 'cheating'),
        throwsA(
          isA<PublicProfileException>()
              .having((e) => e.kind, 'kind',
                  PublicProfileErrorKind.cannotReportSelf)
              .having((e) => e.message, 'message',
                  AppStrings.profileCannotReportSelf),
        ),
      );
    });
  });
}
