import 'package:flutter/material.dart';
import '../theme/app_text_styles.dart';

/// DESIGN.md Bölüm 6: Bölüm Etiketi
/// BÜYÜK HARF (Türkçe kurallarına uygun: i -> İ, ı -> I),
/// Nunito 12/800, muted, harf aralığı 0.08em.
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(
    this.text, {
    super.key,
  });

  String _toTurkishUpper(String input) {
    return input
        .replaceAll('i', 'İ')
        .replaceAll('ı', 'I')
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _toTurkishUpper(text),
      style: AppTextStyles.sectionLabel,
    );
  }
}

