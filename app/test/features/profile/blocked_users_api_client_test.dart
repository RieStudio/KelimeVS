import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/online/data/auth_token_provider.dart';
import 'package:app/features/profile/data/blocked_users_api_client.dart';

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
    if (shouldThrow) throw const SocketException('Network unreachable');
    return FakeHttpClientRequest(statusCode: statusCode, responseBody: responseBody);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    if (shouldThrow) throw const SocketException('Network unreachable');
    return FakeHttpClientRequest(statusCode: statusCode, responseBody: responseBody);
  }

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) async {
    if (shouldThrow) throw const SocketException('Network unreachable');
    return FakeHttpClientRequest(statusCode: statusCode, responseBody: responseBody);
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

class FakeHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
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

class StaticTokenProvider implements AuthTokenProvider {
  final String? token;
  const StaticTokenProvider(this.token);

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => token;
}

void main() {
  test('1. getBlockedUsers 410 aldığında onAccountDeleted tetiklenir', () async {
    bool onDeletedCalled = false;
    final fakeHttp = FakeHttpClient(statusCode: 410, responseBody: '{"error":"account_deleted"}');
    final client = HttpBlockedUsersApiClient(
      authTokenProvider: const StaticTokenProvider('valid_token'),
      clientFactory: () => fakeHttp,
      onAccountDeleted: () {
        onDeletedCalled = true;
      },
    );

    final res = await client.getBlockedUsers();
    expect(res, isEmpty);
    expect(onDeletedCalled, isTrue);
  });

  test('2. blockUser 410 account_deleted aldığında onAccountDeleted tetiklenir', () async {
    bool onDeletedCalled = false;
    final fakeHttp = FakeHttpClient(statusCode: 410, responseBody: '{"error":"account_deleted"}');
    final client = HttpBlockedUsersApiClient(
      authTokenProvider: const StaticTokenProvider('valid_token'),
      clientFactory: () => fakeHttp,
      onAccountDeleted: () {
        onDeletedCalled = true;
      },
    );

    final res = await client.blockUser('match_1');
    expect(res, isA<BlockUserError>());
    expect(onDeletedCalled, isTrue);
  });

  test('3. reportUser 410 match_expired aldığında onAccountDeleted tetiklenmez, isExpired döner', () async {
    bool onDeletedCalled = false;
    final fakeHttp = FakeHttpClient(statusCode: 410, responseBody: '{"error":"match_expired"}');
    final client = HttpBlockedUsersApiClient(
      authTokenProvider: const StaticTokenProvider('valid_token'),
      clientFactory: () => fakeHttp,
      onAccountDeleted: () {
        onDeletedCalled = true;
      },
    );

    final res = await client.reportUser(matchId: 'match_1', reason: 'cheating');
    expect(res, isA<ReportUserError>());
    expect((res as ReportUserError).isExpired, isTrue);
    expect(onDeletedCalled, isFalse);
  });

  test('4. reportUser 409 aldığında isAlreadyReported döner', () async {
    final fakeHttp = FakeHttpClient(statusCode: 409, responseBody: '{"error":"already_reported"}');
    final client = HttpBlockedUsersApiClient(
      authTokenProvider: const StaticTokenProvider('valid_token'),
      clientFactory: () => fakeHttp,
    );

    final res = await client.reportUser(matchId: 'match_1', reason: 'cheating');
    expect(res, isA<ReportUserError>());
    expect((res as ReportUserError).isAlreadyReported, isTrue);
  });

  test('5. reportUser 429 aldığında isDailyLimit döner', () async {
    final fakeHttp = FakeHttpClient(statusCode: 429, responseBody: '{"error":"daily_limit_exceeded"}');
    final client = HttpBlockedUsersApiClient(
      authTokenProvider: const StaticTokenProvider('valid_token'),
      clientFactory: () => fakeHttp,
    );

    final res = await client.reportUser(matchId: 'match_1', reason: 'other');
    expect(res, isA<ReportUserError>());
    expect((res as ReportUserError).isDailyLimit, isTrue);
  });

  test('6. blockUser 400 aldığında isLimitReached döner', () async {
    final fakeHttp = FakeHttpClient(statusCode: 400, responseBody: '{"error":"block_limit_reached"}');
    final client = HttpBlockedUsersApiClient(
      authTokenProvider: const StaticTokenProvider('valid_token'),
      clientFactory: () => fakeHttp,
    );

    final res = await client.blockUser('match_1');
    expect(res, isA<BlockUserError>());
    expect((res as BlockUserError).isLimitReached, isTrue);
  });
}
