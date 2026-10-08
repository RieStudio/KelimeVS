import '../strings/app_strings.dart';

/// Takvim gününe göre göreceli tarih metni üretir.
///
/// Kurallar:
/// - Aynı gün: "Bugün"
/// - 1 gün önce: "Dün"
/// - 2–6 gün önce: "N gün önce"
/// - 7–13 gün önce: "1 hafta önce"
/// - 14–20 gün önce: "2 hafta önce"
/// - 21–27 gün önce: "3 hafta önce"
/// - 28+ gün önce: "gg.aa.yyyy"
String formatMatchDate(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final currentDate = DateTime(current.year, current.month, current.day);
  final targetDate = DateTime(date.year, date.month, date.day);

  final diffDays = currentDate.difference(targetDate).inDays;

  if (diffDays <= 0) {
    return AppStrings.dateToday;
  } else if (diffDays == 1) {
    return AppStrings.dateYesterday;
  } else if (diffDays <= 6) {
    return '$diffDays${AppStrings.daysAgoSuffix}';
  } else if (diffDays <= 13) {
    return AppStrings.oneWeekAgo;
  } else if (diffDays <= 20) {
    return AppStrings.twoWeeksAgo;
  } else if (diffDays <= 27) {
    return AppStrings.threeWeeksAgo;
  } else {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day.$month.$year';
  }
}

String formatMatchDateMs(int epochMs, {DateTime? now}) {
  return formatMatchDate(
    DateTime.fromMillisecondsSinceEpoch(epochMs),
    now: now,
  );
}

