import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/strings/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/answer_bubble.dart';
import '../../../../core/widgets/app_icon_button.dart';
import '../../../../core/widgets/player_avatar.dart';
import '../../../../core/widgets/result_badge.dart';
import '../../game/application/match_providers.dart';
import '../../game/application/objection_provider.dart';
import '../../game/domain/attempt_text_sanitizer.dart';
import '../../game/domain/history/match_history_entry.dart';
import '../../game/domain/match/match_events.dart';
import '../../game/domain/match/match_state.dart';
import '../../game/domain/objection/objection.dart';
import '../../game/domain/text_filter.dart';

enum RoundResultStatus {
  won,
  lost,
  draw,
  incomplete,
}

/// DESIGN.md Bölüm 7: 6) Maç Detayı Ekranı
///
/// docs/design/detail.png referansına birebir uygun:
/// - Üst bar: Geri ikonu + "Maç Detayı"
/// - Özet kartı: "Sen" avatarı, skor (Fredoka 42), ResultBadge, rakip avatar & adı
/// - Tur kartları: "TUR N", soru metni, ResultBadge, 200 ms rotasyonlu ok
/// - Varsayılan açık tur: Kaybedilen son tur; kayıp yoksa son tur
/// - Kart içi: kronolojik cevap balonları (ben sağda, rakip solda)
/// - İtiraz kutusu: o turdaki son reddedilen denemem varsayılan seçili; wrong/nearMiss itiraz edilebilir
class MatchDetailScreen extends ConsumerStatefulWidget {
  final MatchHistoryEntry match;

  const MatchDetailScreen({
    super.key,
    required this.match,
  });

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen> {
  late final Set<int> _expandedRounds;
  final Map<int, int> _selectedAttempts = {};
  final Set<ObjectionKey> _localObjections = {};

  @override
  void initState() {
    super.initState();
    _expandedRounds = {};
    if (widget.match.roundRecords.isNotEmpty) {
      final defaultOpen = _calculateDefaultOpenRound(widget.match);
      _expandedRounds.add(defaultOpen);
    }
  }

  static RoundResultStatus _getRoundStatus(RoundRecord round) {
    if (round.reason == RoundEndReason.forfeit) {
      return RoundResultStatus.incomplete;
    }
    if (round.winnerId == 'me') {
      return RoundResultStatus.won;
    }
    if (round.winnerId != null) {
      return RoundResultStatus.lost;
    }
    return RoundResultStatus.draw;
  }

  int _calculateDefaultOpenRound(MatchHistoryEntry match) {
    if (match.roundRecords.isEmpty) return 0;
    // Kaybettiğim son tur (status == RoundResultStatus.lost; terk edilen tur lost sayılmaz)
    for (int i = match.roundRecords.length - 1; i >= 0; i--) {
      final r = match.roundRecords[i];
      if (_getRoundStatus(r) == RoundResultStatus.lost) {
        return i;
      }
    }
    // Kaybettiğim tur yoksa son tur
    return match.roundRecords.length - 1;
  }

  int? _getSelectedAttempt(int roundIndex, RoundRecord round) {
    if (_selectedAttempts.containsKey(roundIndex)) {
      final selected = _selectedAttempts[roundIndex];
      if (selected != null &&
          selected >= 0 &&
          selected < round.attempts.length &&
          AttemptTextSanitizer.sanitize(round.attempts[selected].rawInput).isNotEmpty) {
        return selected;
      }
    }
    // Varsayılan: o turdaki bana ait son reddedilen ve sanitize edildikten sonra boş olmayan deneme
    for (int j = round.attempts.length - 1; j >= 0; j--) {
      final a = round.attempts[j];
      if (a.playerId == 'me' &&
          a.resultType != AttemptResultType.correct &&
          AttemptTextSanitizer.sanitize(a.rawInput).isNotEmpty) {
        return j;
      }
    }
    return null;
  }

  void _toggleRound(int index) {
    setState(() {
      if (_expandedRounds.contains(index)) {
        _expandedRounds.remove(index);
      } else {
        _expandedRounds.add(index);
      }
    });
  }

  Future<void> _submitObjection(
    int roundIndex,
    int attemptIndex,
    String rawInput,
  ) async {
    final objection = Objection(
      matchId: widget.match.id,
      roundIndex: roundIndex,
      attemptIndex: attemptIndex,
      rawInput: rawInput,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final repo = ref.read(objectionRepositoryProvider);
    await repo.add(objection);

    setState(() {
      _localObjections.add(objection.key);
    });

    ref.invalidate(matchObjectionsProvider(widget.match.id));
  }

  @override
  Widget build(BuildContext context) {
    final textFilter = ref.watch(textFilterProvider);
    final objectionsAsync = ref.watch(matchObjectionsProvider(widget.match.id));
    final savedObjections = objectionsAsync.asData?.value ?? const <ObjectionKey>{};
    final allObjections = {...savedObjections, ..._localObjections};

    final isWinner = widget.match.result == MatchResult.win;
    final isForfeit = widget.match.endType == MatchEndType.forfeit;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Üst Bar: Geri İkonu + "Maç Detayı"
            Padding(
              padding: const EdgeInsets.only(
                left: AppDimens.screenPaddingHorizontal,
                right: AppDimens.screenPaddingHorizontal,
                top: AppDimens.space16,
                bottom: AppDimens.space16,
              ),
              child: Row(
                children: [
                  AppIconButton(
                    icon: AppIcons.back,
                    semanticLabel: AppStrings.back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      AppStrings.matchDetail,
                      style: AppTextStyles.screenTitle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: AppDimens.iconButtonSize),
                ],
              ),
            ),

            // 2. Özet Kartı
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.screenPaddingHorizontal,
              ),
              child: _buildSummaryCard(isWinner: isWinner, isForfeit: isForfeit),
            ),

            const SizedBox(height: AppDimens.space14),

            // 3. Tur Kartları Listesi (Kaydırma çubukları gizli)
            Expanded(
              child: ScrollConfiguration(
                behavior: const ScrollBehavior().copyWith(scrollbars: false),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.screenPaddingHorizontal,
                    0,
                    AppDimens.screenPaddingHorizontal,
                    AppDimens.space24,
                  ),
                  itemCount: widget.match.roundRecords.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppDimens.listSpacing),
                  itemBuilder: (context, index) {
                    final round = widget.match.roundRecords[index];
                    final questionText = widget.match.questionTextForRound(index);
                    final isExpanded = _expandedRounds.contains(index);
                    final selectedAttemptIndex = _getSelectedAttempt(index, round);

                    return _buildRoundCard(
                      roundIndex: index,
                      round: round,
                      questionText: questionText,
                      isExpanded: isExpanded,
                      selectedAttemptIndex: selectedAttemptIndex,
                      textFilter: textFilter,
                      allObjections: allObjections,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required bool isWinner,
    required bool isForfeit,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space20,
        vertical: AppDimens.space16,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppDimens.borderRadiusListCard,
        border: Border.all(
          color: AppColors.mint,
          width: AppDimens.borderThin,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Sol: Benim avatarım ve "Sen"
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PlayerAvatar.selfMatch(
                name: AppStrings.you,
                size: 54,
              ),
              const SizedBox(height: AppDimens.space6),
              Text(
                AppStrings.you,
                style: AppTextStyles.playerName.copyWith(fontSize: 14),
              ),
            ],
          ),

          // Orta: Skor, ResultBadge ve Terk Notu
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.match.myScore} – ${widget.match.opponentScore}',
                  style: AppTextStyles.scoreMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimens.space6),
                ResultBadge(
                  variant: isWinner ? ResultBadgeVariant.won : ResultBadgeVariant.lost,
                ),
                if (isForfeit) ...[
                  const SizedBox(height: AppDimens.space4),
                  Text(
                    isWinner ? AppStrings.opponentLeftMatch : AppStrings.youLeftMatch,
                    style: AppTextStyles.secondaryText.copyWith(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),

          // Sağ: Rakip avatarı ve adı
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerAvatar.opponent(
                name: widget.match.opponentName,
                size: 54,
              ),
              const SizedBox(height: AppDimens.space6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 80),
                child: Text(
                  widget.match.opponentName,
                  style: AppTextStyles.playerName.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoundCard({
    required int roundIndex,
    required RoundRecord round,
    required String questionText,
    required bool isExpanded,
    required int? selectedAttemptIndex,
    required TextFilter textFilter,
    required Set<ObjectionKey> allObjections,
  }) {
    final status = _getRoundStatus(round);
    final String statusText;
    final Color statusColor;
    final String semanticStatus;

    switch (status) {
      case RoundResultStatus.won:
        statusText = AppStrings.roundLabelWon;
        statusColor = AppColors.primary;
        semanticStatus = AppStrings.won.toLowerCase();
        break;
      case RoundResultStatus.lost:
        statusText = AppStrings.roundLabelLost;
        statusColor = AppColors.dangerText;
        semanticStatus = AppStrings.lost.toLowerCase();
        break;
      case RoundResultStatus.draw:
        statusText = AppStrings.roundLabelDraw;
        statusColor = AppColors.muted;
        semanticStatus = AppStrings.draw.toLowerCase();
        break;
      case RoundResultStatus.incomplete:
        statusText = AppStrings.roundLabelIncomplete;
        statusColor = AppColors.muted;
        semanticStatus = AppStrings.incomplete.toLowerCase();
        break;
    }

    final attempts = round.attempts;
    final validAttemptIndices = <int>[];
    for (int j = 0; j < attempts.length; j++) {
      if (AttemptTextSanitizer.sanitize(attempts[j].rawInput).isNotEmpty) {
        validAttemptIndices.add(j);
      }
    }

    final TurnAttempt? selectedAttempt = (selectedAttemptIndex != null &&
            selectedAttemptIndex >= 0 &&
            selectedAttemptIndex < attempts.length &&
            AttemptTextSanitizer.sanitize(attempts[selectedAttemptIndex].rawInput).isNotEmpty)
        ? attempts[selectedAttemptIndex]
        : null;

    final isObjected = selectedAttemptIndex != null &&
        allObjections.contains(
          ObjectionKey(
            matchId: widget.match.id,
            roundIndex: roundIndex,
            attemptIndex: selectedAttemptIndex,
          ),
        );

    return Semantics(
      label: '${AppStrings.roundUpperPrefix}${roundIndex + 1}, $semanticStatus, $questionText',
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppDimens.borderRadiusListCard,
          border: Border.all(
            color: AppColors.mint,
            width: AppDimens.borderThin,
          ),
        ),
        child: Column(
          children: [
            // Kart Başlığı (Dokunmayla açılır/kapanır)
            Semantics(
              button: true,
              expanded: isExpanded,
              label: '${AppStrings.roundUpperPrefix}${roundIndex + 1}, $semanticStatus, $questionText',
              child: InkWell(
                onTap: () => _toggleRound(roundIndex),
                borderRadius: AppDimens.borderRadiusListCard,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.space16,
                    vertical: AppDimens.space14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text:
                                        '${AppStrings.roundUpperPrefix}${roundIndex + 1}${AppStrings.dotSeparator}',
                                    style: AppTextStyles.sectionLabel,
                                  ),
                                  TextSpan(
                                    text: statusText,
                                    style: AppTextStyles.sectionLabel.copyWith(
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppDimens.space4),
                            Text(
                              questionText,
                              style: AppTextStyles.questionText,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppDimens.space12),
                      AnimatedRotation(
                        turns: isExpanded ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: const AppIcon(
                          AppIcons.arrowList,
                          size: 16,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Açık Kart İçeriği
            if (isExpanded) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.space16,
                  0,
                  AppDimens.space16,
                  AppDimens.space16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(color: AppColors.mint, height: 1),
                    const SizedBox(height: AppDimens.space12),

                    if (validAttemptIndices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppDimens.space12,
                        ),
                        child: Text(
                          AppStrings.noAttemptsInRound,
                          style: AppTextStyles.secondaryText.copyWith(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else ...[
                      // Denemeler Listesi (Kronolojik, sadece temizlenmiş hali boş olmayanlar)
                      for (int i = 0; i < validAttemptIndices.length; i++) ...[
                        if (i > 0)
                          const SizedBox(height: AppDimens.bubbleSpacing),
                        _buildAttemptBubbleItem(
                          roundIndex: roundIndex,
                          attemptIndex: validAttemptIndices[i],
                          attempt: attempts[validAttemptIndices[i]],
                          isSelected: validAttemptIndices[i] == selectedAttemptIndex,
                          textFilter: textFilter,
                        ),
                      ],

                      // İtiraz Kutusu (Varsa seçili reddedilen cevap için)
                      if (selectedAttempt != null) ...[
                        const SizedBox(height: AppDimens.space12),
                        _buildObjectionBox(
                          roundIndex: roundIndex,
                          attemptIndex: selectedAttemptIndex!,
                          attempt: selectedAttempt,
                          isObjected: isObjected,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAttemptBubbleItem({
    required int roundIndex,
    required int attemptIndex,
    required TurnAttempt attempt,
    required bool isSelected,
    required TextFilter textFilter,
  }) {
    final isMe = attempt.playerId == 'me';
    final isRejected = attempt.resultType != AttemptResultType.correct;
    final sanitizedInput = AttemptTextSanitizer.sanitize(attempt.rawInput);
    final displayText = isMe ? sanitizedInput : textFilter.apply(sanitizedInput);

    // Sadece kendi reddedilen ve boş olmayan cevaplarıma dokununca seçim aktifleşir
    final canSelect = isMe && isRejected && sanitizedInput.isNotEmpty;

    return AnswerBubble(
      text: displayText,
      isMe: isMe,
      isRejected: isRejected,
      isSelected: isSelected && canSelect,
      onTap: canSelect
          ? () {
              setState(() {
                _selectedAttempts[roundIndex] = attemptIndex;
              });
            }
          : null,
    );
  }

  Widget _buildObjectionBox({
    required int roundIndex,
    required int attemptIndex,
    required TurnAttempt attempt,
    required bool isObjected,
  }) {
    // 1. Zaten söylenmiş cevap (itiraz linki yok)
    if (attempt.resultType == AttemptResultType.repeated) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space16,
          vertical: AppDimens.space12,
        ),
        decoration: BoxDecoration(
          color: AppColors.dangerSurface,
          borderRadius: AppDimens.borderRadiusAlertBox,
          border: Border.all(
            color: AppColors.dangerSoft,
            width: AppDimens.borderThin,
          ),
        ),
        child: Text(
          AppStrings.alreadySaidNotice,
          style: AppTextStyles.bodyText.copyWith(
            color: AppColors.dangerDark,
            fontSize: 13,
          ),
        ),
      );
    }

    // 2. wrong veya nearMiss: İtiraz gönderildi ya da itiraz linki
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.space16,
        vertical: AppDimens.space6,
      ),
      decoration: BoxDecoration(
        color: AppColors.dangerSurface,
        borderRadius: AppDimens.borderRadiusAlertBox,
        border: Border.all(
          color: AppColors.dangerSoft,
          width: AppDimens.borderThin,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppStrings.objectionPrompt(attempt.rawInput),
              style: AppTextStyles.bodyText.copyWith(
                color: AppColors.dangerDark,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: AppDimens.space10),
          if (isObjected)
            Text(
              AppStrings.objectionSent,
              style: AppTextStyles.bodyText.copyWith(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            )
          else
            Semantics(
              button: true,
              label: AppStrings.appeal,
              child: InkWell(
                onTap: () => _submitObjection(
                  roundIndex,
                  attemptIndex,
                  attempt.rawInput,
                ),
                borderRadius: AppDimens.borderRadiusBadge,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppDimens.minTouchTarget,
                    minWidth: 48,
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      AppStrings.appeal,
                      style: AppTextStyles.bodyText.copyWith(
                        color: AppColors.dangerText,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
