import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Oyun genelinde boş durum kartları için kullanılan ortak kart kabuğu ve dekorasyonu.
///
/// Sıralama ekranı boş durumu ile ana sayfadaki "Arkadaşınla Oyna" butonunun
/// kalın çerçeve stiline (`AppDimens.borderThick`, `AppColors.ink`, `AppDimens.borderRadiusListCard`
/// ve `AppDimens.shadowQuestionCard`) tam uyumludur.
class EmptyStateCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double? borderWidth;
  final List<BoxShadow>? boxShadow;

  const EmptyStateCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppDimens.space24),
    this.color,
    this.borderColor,
    this.borderWidth,
    this.boxShadow,
  });

  /// Boş durum kartları için standart kutu dekorasyonu.
  static BoxDecoration buildDecoration({
    Color color = AppColors.card,
    Color borderColor = AppColors.ink,
    double borderWidth = AppDimens.borderThick,
    List<BoxShadow> boxShadow = AppDimens.shadowQuestionCard,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: AppDimens.borderRadiusListCard,
      border: Border.all(
        color: borderColor,
        width: borderWidth,
      ),
      boxShadow: boxShadow,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: buildDecoration(
        color: color ?? AppColors.card,
        borderColor: borderColor ?? AppColors.ink,
        borderWidth: borderWidth ?? AppDimens.borderThick,
        boxShadow: boxShadow ?? AppDimens.shadowQuestionCard,
      ),
      child: child,
    );
  }
}

