// Geliştirici hata ayıklama sayfası (yalnızca kDebugMode).
// Düz metin arayüz: DESIGN.md bileşenleri ve stil tokenları kullanılmaz.

import 'dart:async';
import 'package:flutter/material.dart';

import '../online/data/matchmaking_client.dart';
import '../online/data/online_match_client.dart';
import '../online/domain/models/online_match_state.dart';

/// Sunucu protokolünü gerçek zamanlı test etmek için kullanılan geliştirici sayfası.
class OnlineTestPage extends StatefulWidget {
  final MatchmakingClient? matchmakingClient;
  final OnlineMatchClient? matchClient;

  const OnlineTestPage({
    super.key,
    this.matchmakingClient,
    this.matchClient,
  });

  @override
  State<OnlineTestPage> createState() => _OnlineTestPageState();
}

class _OnlineTestPageState extends State<OnlineTestPage> {
  final TextEditingController _nameController =
      TextEditingController(text: 'Test');
  final TextEditingController _answerController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  final List<String> _logs = [];

  MatchmakingClient? _matchmakingClient;
  OnlineMatchClient? _matchClient;
  StreamSubscription<MatchmakingEvent>? _matchmakingSub;
  StreamSubscription<OnlineMatchEvent>? _matchSub;
  Timer? _tickerTimer;

  bool _isQueueing = false;
  String? _activeMatchId;
  String? _opponentName;
  OnlineMatchState? _currentState;

  @override
  void initState() {
    super.initState();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _currentState != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _matchmakingSub?.cancel();
    _matchSub?.cancel();
    _matchmakingClient?.dispose();
    _matchClient?.dispose();
    _nameController.dispose();
    _answerController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _addLog(String text) {
    if (!mounted) return;
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.add('[$timeStr] $text');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startQueue() async {
    if (_isQueueing) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isQueueing = true;
      _activeMatchId = null;
      _opponentName = null;
      _currentState = null;
    });

    _addLog('Eşleştirme başlatılıyor (Ad: $name)...');

    _matchmakingClient = widget.matchmakingClient ?? MatchmakingClient();
    _matchmakingSub = _matchmakingClient!.events.listen(
      _handleMatchmakingEvent,
      onError: (e) => _addLog('Eşleştirme hatası: $e'),
    );

    try {
      await _matchmakingClient!.start(name);
    } catch (e) {
      _addLog('Başlatma hatası: $e');
      setState(() {
        _isQueueing = false;
      });
    }
  }

  void _handleMatchmakingEvent(MatchmakingEvent event) {
    switch (event) {
      case MatchmakingConnecting():
        _addLog('connecting: Eşleştirme sunucusuna bağlanılıyor...');
      case MatchmakingQueued():
        _addLog('queued: Kuyruğa girildi, rakip aranıyor...');
      case MatchmakingMatched(:final matchId, :final opponentName):
        _addLog('matched: Eşleşme bulundu (Rakip: $opponentName)');
        setState(() {
          _isQueueing = false;
          _activeMatchId = matchId;
          _opponentName = opponentName;
        });
        _connectToMatch(matchId);
      case MatchmakingCancelled():
        _addLog('cancelled: Kuyruktan çıkıldı.');
        setState(() {
          _isQueueing = false;
        });
      case MatchmakingNoOpponent():
        _addLog('noOpponent: Süre doldu, botlu maça düşülecek');
        setState(() {
          _isQueueing = false;
        });
      case MatchmakingUnavailable(:final reason):
        _addLog('unavailable ($reason): botlu maça düşülecek');
        setState(() {
          _isQueueing = false;
        });
      case MatchmakingFailed(:final reason):
        _addLog('failed: Eşleştirme başarısız ($reason)');
        setState(() {
          _isQueueing = false;
        });
    }
  }

  Future<void> _cancelQueue() async {
    if (!_isQueueing || _matchmakingClient == null) return;
    _addLog('Kuyruk iptal ediliyor...');
    await _matchmakingClient!.cancel();
    setState(() {
      _isQueueing = false;
    });
  }

  Future<void> _connectToMatch(String matchId) async {
    _addLog('Maç odasına bağlanılıyor...');
    _matchClient = widget.matchClient ?? OnlineMatchClient();
    _matchSub = _matchClient!.events.listen(
      _handleOnlineMatchEvent,
      onError: (e) => _addLog('Maç odası akış hatası: $e'),
    );

    await _matchClient!.connect(matchId);
  }

  void _handleOnlineMatchEvent(OnlineMatchEvent event) {
    switch (event) {
      case OnlineMatchConnected():
        _addLog('connected: Maç odasına bağlanıldı.');
      case OnlineMatchStateUpdate(:final state):
        setState(() {
          _currentState = state;
        });
      case OnlineMatchFeedback(:final kind, :final reason):
        _addLog('feedback: $kind ${reason != null ? '($reason)' : ''}');
      case OnlineMatchFinal(:final result):
        _addLog(
          'final: Maç sonuçlandı (Kazandım: ${result.winnerIsMe}, Skor: ${result.myScore}-${result.opponentScore}, Bitiş: ${result.endedBy})',
        );
      case OnlineMatchVoided(:final reason):
        _addLog('voided: Maç iptal edildi ($reason)');
      case OnlineMatchDisconnected(:final reason):
        _addLog('disconnected: Bağlantı koptu ($reason)');
      case OnlineMatchError(:final message):
        _addLog('error: $message');
    }
  }

  void _submitAnswer() {
    if (_matchClient == null) return;
    final text = _answerController.text.trim();
    if (text.isEmpty) return;

    final sent = _matchClient!.submit(text);
    if (sent) {
      _addLog('Gönderildi: "$text"');
      _answerController.clear();
    } else {
      _addLog('Gönderilemedi (Cooldown veya bağlantı yok)');
    }
  }

  Future<void> _leaveMatch() async {
    if (_matchClient == null) return;
    _addLog('Maçtan çıkılıyor (forfeit)...');
    await _matchClient!.leave();
  }

  @override
  Widget build(BuildContext context) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final remainingSec = _currentState != null
        ? (_currentState!.kalanSureMs(nowMs) / 1000).ceil()
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Test (Protokol v1)'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Eşleştirme Girişi
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Oyuncu Adı',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      enabled: !_isQueueing && _activeMatchId == null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: (!_isQueueing && _activeMatchId == null)
                        ? _startQueue
                        : null,
                    child: const Text('Kuyruğa gir'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isQueueing ? _cancelQueue : null,
                    child: const Text('İptal'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 2. Canlı Maç Bilgileri & Durum Satırı
              if (_activeMatchId != null) ...[
                Container(
                  padding: const EdgeInsets.all(8.0),
                  color: Colors.grey.shade200,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Maç ID: $_activeMatchId | Rakip: ${_opponentName ?? '-'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (_currentState != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Faz: ${_currentState!.phase.name} | Tur: ${_currentState!.roundNumber} | '
                          'Skor: ${_currentState!.myScore}-${_currentState!.opponentScore} | '
                          '${_currentState!.turnIsMine ? 'Sıra BENDE' : 'Sıra RAKİPTE'} | '
                          'Kalan: ${remainingSec != null && remainingSec > 0 ? '${remainingSec}s' : '0s'}',
                        ),
                        if (_currentState!.question != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Soru: ${_currentState!.question!.text}',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _answerController,
                        decoration: const InputDecoration(
                          hintText: 'Cevap yaz...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _submitAnswer(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _submitAnswer,
                      child: const Text('Gönder'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _leaveMatch,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade100,
                      ),
                      child: const Text('Maçtan çık'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // 3. Olay Günlüğü Başlığı
              const Text(
                'Olay Günlüğü:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),

              // 4. Kaydırılabilir Olay Günlüğü
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    color: Colors.black.withAlpha(10),
                  ),
                  child: ListView.builder(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          _logs[index],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

