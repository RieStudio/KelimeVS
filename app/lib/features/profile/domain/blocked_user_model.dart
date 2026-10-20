class BlockedUser {
  final String id;
  final String nickname;
  final int blockedAt;

  const BlockedUser({
    required this.id,
    required this.nickname,
    required this.blockedAt,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    return BlockedUser(
      id: json['id'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      blockedAt: (json['blockedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nickname': nickname,
      'blockedAt': blockedAt,
    };
  }
}

