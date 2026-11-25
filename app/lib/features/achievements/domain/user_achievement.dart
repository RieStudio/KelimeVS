/// Kullanıcının açtığı bir başarım kaydı.
class UserAchievement {
  final String id;
  final int unlockedAt;
  final int count;

  const UserAchievement({
    required this.id,
    required this.unlockedAt,
    this.count = 1,
  });

  factory UserAchievement.fromJson(Map<String, dynamic> json) {
    final rawCount = (json['count'] as num?)?.toInt() ?? 1;
    return UserAchievement(
      id: json['id'] as String? ?? '',
      unlockedAt: (json['unlockedAt'] ?? json['unlocked_at'] as num?)?.toInt() ?? 0,
      count: rawCount < 1 ? 1 : rawCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'unlockedAt': unlockedAt,
        'count': count,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAchievement &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          unlockedAt == other.unlockedAt &&
          count == other.count;

  @override
  int get hashCode => Object.hash(id, unlockedAt, count);
}
