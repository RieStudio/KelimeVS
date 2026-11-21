import { describe, expect, it } from 'vitest';
import {
  toClientAttempt,
  filterStateForPlayer,
  buildClientState,
  buildFinalMessage,
  type MatchState,
} from '../src/storage';
import type { TurnAttempt, RoundRecord, MatchConfig } from '../src/engine';

describe('Storage & Protocol Masking Integration', () => {
  const p1 = 'user_111';
  const p2 = 'user_222';

  const defaultMockConfig: MatchConfig = {
    roundsToWin: 2,
    answerSeconds: 15,
    graceMs: 500,
    nearMissPerRound: 1,
    minAnswersPerQuestion: 10,
    minSubmitIntervalMs: 200,
    maxAttemptsPerTurn: 3,
  };

  describe('1. toClientAttempt Tek Fabrika Fonksiyonu', () => {
    it('viewerUid ile attempt.playerId eşleştiğinde (mine: true) metin ASLA maskelenmez', () => {
      const myAttempt: TurnAttempt = {
        playerId: p1,
        rawInput: 'orospu',
        resultType: 'wrong',
        nowMs: 1000,
        isClose: false,
        hintShown: false,
      };

      const dto = toClientAttempt({ attempt: myAttempt, viewerUid: p1 });

      expect(dto.mine).toBe(true);
      expect(dto.text).toBe('orospu'); // Ham metin korunur
      expect(dto.result).toBe('wrong');
    });

    it('viewerUid ile attempt.playerId eşleşmediğinde (mine: false) metin maskelenir', () => {
      const oppAttempt: TurnAttempt = {
        playerId: p2,
        rawInput: 'orospu',
        resultType: 'wrong',
        nowMs: 1000,
        isClose: false,
        hintShown: false,
      };

      const dto = toClientAttempt({ attempt: oppAttempt, viewerUid: p1 });

      expect(dto.mine).toBe(false);
      expect(dto.text).toBe('o*****'); // Maskeli metin
      expect(dto.result).toBe('wrong');
    });

    it('masum kelimeler rakip için de maskelenmeden geçer', () => {
      const oppAttempt: TurnAttempt = {
        playerId: p2,
        rawInput: 'elma',
        resultType: 'wrong',
        nowMs: 1000,
        isClose: false,
        hintShown: false,
      };

      const dto = toClientAttempt({ attempt: oppAttempt, viewerUid: p1 });

      expect(dto.mine).toBe(false);
      expect(dto.text).toBe('elma');
    });

    it('doğru cevaplarda displayText varsa displayText maskeden geçer (masumsa korunur)', () => {
      const correctAttempt: TurnAttempt = {
        playerId: p2,
        rawInput: 'claude',
        displayText: 'Claude',
        resultType: 'correct',
        nowMs: 1000,
        isClose: false,
        hintShown: false,
      };

      const dto = toClientAttempt({ attempt: correctAttempt, viewerUid: p1 });

      expect(dto.mine).toBe(false);
      expect(dto.text).toBe('Claude');
      expect(dto.result).toBe('correct');
    });

    it('hintShown ve viaPowerup bayrakları DTO serileştirmede korunur', () => {
      const powerupAttempt: TurnAttempt = {
        playerId: p2,
        rawInput: 'orospu',
        resultType: 'wrong',
        nowMs: 1000,
        isClose: false,
        hintShown: true,
        viaPowerup: true,
      };

      const dto = toClientAttempt({ attempt: powerupAttempt, viewerUid: p1 });

      expect(dto.hintShown).toBe(true);
      expect(dto.viaPowerup).toBe(true);
      expect(dto.text).toBe('o*****');
    });
  });

  describe('2. buildClientState / filterStateForPlayer WebSocket State Mesajı', () => {
    function createMockMatchState(attempts: TurnAttempt[]): MatchState {
      return {
        config: defaultMockConfig,
        phase: 'roundActive',
        playerIds: [p1, p2],
        scores: { [p1]: 0, [p2]: 0 },
        turnPlayerId: p1,
        decisiveRounds: 0,
        totalRoundsPlayed: 0,
        currentQuestion: { id: 'q1', text: 'Örnek soru', categoryId: 'test', answers: [] },
        usedAnswerIds: new Set(),
        usedQuestionIds: new Set(),
        lastSubmitTimes: {},
        currentTurnAttempts: 0,
        endedBy: null,
        winnerId: null,
        currentRoundAttempts: attempts,
        deadlineMs: 20000,
        remainingNearMisses: { [p1]: 1, [p2]: 1 },
        roundHistory: [],
      };
    }

    it('canlı maç akışında (roundActive) rakip denemeleri maskeli, oyuncunun kendi denemesi ham gider', () => {
      const attempts: TurnAttempt[] = [
        {
          playerId: p1,
          rawInput: 'sikerim',
          resultType: 'wrong',
          nowMs: 1000,
          isClose: false,
          hintShown: false,
        },
        {
          playerId: p2,
          rawInput: 'orospu',
          resultType: 'wrong',
          nowMs: 2000,
          isClose: false,
          hintShown: false,
        },
      ];

      const state = createMockMatchState(attempts);

      // p1'in gözünden state mesajı
      const p1Msg = buildClientState({
        state,
        playerUid: p1,
        opponentUid: p2,
        opponentName: 'RakipOyuncu',
        opponentConnected: true,
        serverNowMs: 3000,
      });

      // p1 kendisininkini ham, rakibininkini maskeli görür
      expect(p1Msg.attempts[0].mine).toBe(true);
      expect(p1Msg.attempts[0].text).toBe('sikerim'); // Kendi cevabı ham!
      expect(p1Msg.attempts[1].mine).toBe(false);
      expect(p1Msg.attempts[1].text).toBe('o*****'); // Rakip cevabı maskeli!

      // p2'nin gözünden state mesajı
      const p2Msg = buildClientState({
        state,
        playerUid: p2,
        opponentUid: p1,
        opponentName: 'Oyuncu1',
        opponentConnected: true,
        serverNowMs: 3000,
      });

      // p2 kendisininkini ham, p1'inkini maskeli görür
      expect(p2Msg.attempts[0].mine).toBe(false);
      expect(p2Msg.attempts[0].text).toBe('s******'); // p1'in küfrü p2'ye maskeli!
      expect(p2Msg.attempts[1].mine).toBe(true);
      expect(p2Msg.attempts[1].text).toBe('orospu'); // p2'nin kendi cevabı ham!

      // Orijinal sunucu durumu (MatchState) ASLA değişmedi
      expect(state.currentRoundAttempts[0].rawInput).toBe('sikerim');
      expect(state.currentRoundAttempts[1].rawInput).toBe('orospu');
    });

    it('yeniden bağlanma (reconnect) anlık görüntüsünde de rakip denemeleri maskeli kalır', () => {
      const attempts: TurnAttempt[] = [
        {
          playerId: p2,
          rawInput: 's i k',
          resultType: 'wrong',
          nowMs: 1000,
          isClose: false,
          hintShown: false,
        },
      ];

      const state = createMockMatchState(attempts);

      const reconnectMsg = filterStateForPlayer({
        state,
        playerUid: p1,
        opponentUid: p2,
        opponentName: 'Rakip',
        opponentConnected: true,
        serverNowMs: 5000,
      });

      expect(reconnectMsg.attempts[0].mine).toBe(false);
      expect(reconnectMsg.attempts[0].text).toBe('s****');
    });
  });

  describe('3. buildFinalMessage WebSocket Final Mesajı', () => {
    it('maç sonu tur geçmişinde (rounds[].attempts) rakip cevapları maskelenir, kendi cevapları ham kalır', () => {
      const round1: RoundRecord = {
        questionId: 'q1',
        starterPlayerId: p1,
        attempts: [
          {
            playerId: p1,
            rawInput: 'orospu',
            resultType: 'wrong',
            nowMs: 1000,
            isClose: false,
            hintShown: false,
          },
          {
            playerId: p2,
            rawInput: 'sikerim',
            resultType: 'wrong',
            nowMs: 2000,
            isClose: false,
            hintShown: false,
          },
        ],
        winnerId: p1,
        reason: 'timeout',
      };

      const finalState: MatchState = {
        config: defaultMockConfig,
        phase: 'matchFinished',
        playerIds: [p1, p2],
        scores: { [p1]: 2, [p2]: 0 },
        turnPlayerId: null,
        decisiveRounds: 1,
        totalRoundsPlayed: 1,
        currentQuestion: null,
        usedAnswerIds: new Set(),
        usedQuestionIds: new Set(),
        lastSubmitTimes: {},
        currentTurnAttempts: 0,
        endedBy: 'normal',
        currentRoundAttempts: [],
        deadlineMs: 0,
        remainingNearMisses: { [p1]: 1, [p2]: 1 },
        roundHistory: [round1],
        winnerId: p1,
      };

      const p1Final = buildFinalMessage({
        state: finalState,
        playerUid: p1,
        opponentUid: p2,
        opponentName: 'RakipOyuncu',
      });

      // p1'in turlarındaki denemeler:
      const p1Attempts = p1Final.rounds[0].attempts;
      expect(p1Attempts[0].mine).toBe(true);
      expect(p1Attempts[0].text).toBe('orospu'); // Kendi cevabı ham!
      expect(p1Attempts[1].mine).toBe(false);
      expect(p1Attempts[1].text).toBe('s******'); // Rakip cevabı maskeli!

      // Orijinal sunucu durumu bozulmamıştır
      expect(round1.attempts[0].rawInput).toBe('orospu');
      expect(round1.attempts[1].rawInput).toBe('sikerim');
    });
  });

  describe('4. Sızıntı Önleme Güvenlik Denetimi (Guard Test)', () => {
    it('toClientAttempt kullanılmadan üretilen veya rakibe ham küfür sızdıran DTO olamaz', () => {
      const dirtyAttempt: TurnAttempt = {
        playerId: 'attacker',
        rawInput: 'orospucocugu',
        resultType: 'wrong',
        nowMs: 500,
        isClose: false,
        hintShown: false,
      };

      const victimAttempt = toClientAttempt({
        attempt: dirtyAttempt,
        viewerUid: 'victim',
      });

      // Asla ham metin içermemeli
      expect(victimAttempt.text).not.toBe('orospucocugu');
      expect(victimAttempt.text).toBe('o***********');
    });
  });
});
