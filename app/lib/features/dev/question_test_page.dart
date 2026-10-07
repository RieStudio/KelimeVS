import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/icons/app_icons.dart';
import '../../core/strings/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_widgets.dart';
import '../game/data/local_question_repository.dart';
import '../game/data/question_repository.dart';
import '../game/domain/answer_matcher.dart';
import '../game/domain/models.dart';

class QuestionTestPage extends StatefulWidget {
  final QuestionRepository? repository;

  const QuestionTestPage({
    super.key,
    this.repository,
  });

  @override
  State<QuestionTestPage> createState() => _QuestionTestPageState();
}

class _QuestionTestPageState extends State<QuestionTestPage> {
  late final QuestionRepository _repository;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isLoading = true;
  String? _errorMessage;
  List<Question> _questions = [];
  Question? _currentQuestion;
  AnswerMatcher? _matcher;
  final Set<String> _usedAnswerIds = {};
  final List<String> _givenAnswersHistory = [];

  String? _lastResultText;
  Color _lastResultColor = AppColors.ink;

  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? const LocalQuestionRepository();
    _loadQuestions();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loaded = await _repository.loadAll();
      if (!mounted) return;

      setState(() {
        _questions = loaded;
        _isLoading = false;
        if (_questions.isNotEmpty) {
          _pickRandomQuestion();
        } else {
          _errorMessage = AppStrings.noQuestionsFound;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _pickRandomQuestion() {
    if (_questions.isEmpty) return;
    final nextIndex = _random.nextInt(_questions.length);
    final question = _questions[nextIndex];

    setState(() {
      _currentQuestion = question;
      _matcher = AnswerMatcher(question);
      _usedAnswerIds.clear();
      _givenAnswersHistory.clear();
      _lastResultText = null;
      _textController.clear();
    });
    _focusNode.requestFocus();
  }

  void _submit() {
    final matcher = _matcher;
    if (matcher == null) return;

    final input = _textController.text;
    final result = matcher.check(input, _usedAnswerIds);

    setState(() {
      switch (result) {
        case MatchResultCorrect(:final answer):
          _usedAnswerIds.add(answer.id);
          _givenAnswersHistory.insert(0, answer.display);
          _lastResultText = '${AppStrings.resultCorrect} (${answer.display})';
          _lastResultColor = AppColors.primary;
          _textController.clear();
          if (matcher.isExhausted(_usedAnswerIds)) {
            _lastResultText = '${AppStrings.resultCorrect} - ${AppStrings.resultExhausted}';
          }
          break;

        case MatchResultRepeated(:final answer):
          _lastResultText = '${AppStrings.resultRepeated} (${answer.display})';
          _lastResultColor = AppColors.dangerDark;
          _textController.clear();
          break;

        case MatchResultWrong():
          _lastResultText = AppStrings.resultWrong;
          _lastResultColor = AppColors.danger;
          _textController.clear();
          break;

        case MatchResultEmpty():
          _lastResultText = AppStrings.resultEmpty;
          _lastResultColor = AppColors.muted;
          break;
      }
    });

    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          AppStrings.questionTestTitle,
          style: AppTextStyles.screenTitle,
        ),
        leading: Center(
          child: AppIconButton(
            icon: AppIcons.back,
            semanticLabel: 'Geri',
            onTap: () => Navigator.pop(context),
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: Text(
                  AppStrings.loadingQuestions,
                  style: AppTextStyles.subtitle,
                ),
              )
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimens.space20),
                      child: Text(
                        _errorMessage!,
                        style: AppTextStyles.secondaryText.copyWith(
                          color: AppColors.dangerDark,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final question = _currentQuestion;
    final matcher = _matcher;
    if (question == null || matcher == null) {
      return const SizedBox.shrink();
    }

    final remainingCount = matcher.remaining(_usedAnswerIds);

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.screenPaddingHorizontal,
        vertical: AppDimens.screenPaddingTop,
      ),
      children: [
        // Kategori Etiketi
        SectionLabel('${AppStrings.categoryPrefix}${question.categoryId}'),
        const SizedBox(height: AppDimens.space8),

        // Soru Kartı (DESIGN.md Bölüm 6)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDimens.space20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppDimens.borderRadiusQuestionCard,
            border: Border.all(
              color: AppColors.ink,
              width: AppDimens.borderThick,
            ),
            boxShadow: AppDimens.shadowQuestionCard,
          ),
          child: Text(
            question.text,
            style: AppTextStyles.questionText,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppDimens.space16),

        // Kalan Cevap Sayısı
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${AppStrings.remainingAnswersPrefix}$remainingCount / ${question.answers.length}',
              style: AppTextStyles.playerName,
            ),
            if (matcher.isExhausted(_usedAnswerIds))
              const ResultBadge.won(),
          ],
        ),
        const SizedBox(height: AppDimens.space16),

        // Giriş Alanı + Gönder Butonu (DESIGN.md Bölüm 6)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                height: AppDimens.inputHeight,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: AppDimens.borderRadiusInput,
                  border: Border.all(
                    color: AppColors.ink,
                    width: AppDimens.borderThick,
                  ),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  style: AppTextStyles.inputField,
                  decoration: const InputDecoration(
                    hintText: AppStrings.inputPlaceholder,
                    hintStyle: AppTextStyles.inputField,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppDimens.space10),
            // Gönder Butonu (54x54, primary, gölge 0 4px 0 ink)
            Semantics(
              button: true,
              label: AppStrings.send,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _submit,
                child: Container(
                  width: AppDimens.inputHeight,
                  height: AppDimens.inputHeight,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: AppDimens.borderRadiusInput,
                    boxShadow: AppDimens.shadowSendButton,
                  ),
                  alignment: Alignment.center,
                  child: const AppIcon(
                    AppIcons.arrowSend,
                    color: AppColors.card,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.space16),

        // Sonuç Bildirimi Metni
        if (_lastResultText != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.space14,
              vertical: AppDimens.space10,
            ),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppDimens.borderRadiusBadge,
              border: Border.all(
                color: _lastResultColor,
                width: AppDimens.borderThin,
              ),
            ),
            child: Text(
              _lastResultText!,
              style: AppTextStyles.playerName.copyWith(
                color: _lastResultColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppDimens.space16),
        ],

        // Yeni Soru Butonu
        SecondaryButton(
          text: AppStrings.newQuestion,
          onPressed: _pickRandomQuestion,
        ),
        const SizedBox(height: AppDimens.space24),

        // Söylenen Cevaplar Listesi
        const SectionLabel(AppStrings.givenAnswers),
        const SizedBox(height: AppDimens.space10),
        if (_givenAnswersHistory.isEmpty)
          const Text(
            '-',
            style: AppTextStyles.secondaryText,
          )
        else
          Wrap(
            spacing: AppDimens.space8,
            runSpacing: AppDimens.space8,
            children: _givenAnswersHistory.map((ans) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.space12,
                  vertical: AppDimens.space6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bright,
                  borderRadius: AppDimens.borderRadiusBubble,
                  border: Border.all(
                    color: AppColors.ink,
                    width: AppDimens.borderThin,
                  ),
                ),
                child: Text(
                  ans,
                  style: AppTextStyles.answerBubble,
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: AppDimens.space24),
      ],
    );
  }
}

