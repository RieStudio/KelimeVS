import { describe, expect, it } from 'vitest';
import {
  MatchEngine,
  type MatchConfig,
  type Question,
} from '../../src/engine';
import { filterStateForPlayer, buildFinalMessage } from '../../src/storage';

describe('Alias Canonical Display Text in State and Final Messages', () => {
  const sampleQuestion: Question = {
    id: 'q_teams',
    categoryId: 'spor',
    text: 'İstanbul futbol kulüpleri',
    answers: [
      {
        id: 'besiktas',
        display: 'Beşiktaş',
        aliases: ['besiktas', 'bjk', 'kara kartal'],
      },
      {
        id: 'galatasaray',
        display: 'Galatasaray',
        aliases: ['galatasaray', 'gs', 'cimbom'],
      },
      {
        id: 'fenerbahce',
        display: 'Fenerbahçe',
        aliases: ['fenerbahce', 'fb', 'kanarya'],
      },
    ],
  };

  const config: MatchConfig = {
    roundsToWin: 2,
    answerSeconds: 15,
    graceMs: 500,
    nearMissPerRound: 1,
    minAnswersPerQuestion: 3,
    minSubmitIntervalMs: 600,
    maxAttemptsPerTurn: 25,
  };

  it('1. Alias ile girilen doğru cevap balonda ana cevap (answer.display) olarak döner', () => {
    let { state } = MatchEngine.start({
      config,
      playerIds: ['p1', 'p2'],
      questions: [sampleQuestion],
      nowMs: 1000,
      questionOrder: ['q_teams'],
    });

    // p1 alias 'bjk' girer
    const res = MatchEngine.submit({
      state,
      playerId: 'p1',
      rawInput: 'bjk',
      nowMs: 2000,
    });

    state = res.state;

    // TurnAttempt doğrulaması: rawInput 'bjk', displayText 'Beşiktaş'
    expect(state.currentRoundAttempts).toHaveLength(1);
    const attempt = state.currentRoundAttempts[0];
    expect(attempt.rawInput).toBe('bjk');
    expect(attempt.displayText).toBe('Beşiktaş');
    expect(attempt.resultType).toBe('correct');

    // filterStateForPlayer (p1 ve p2 için state.attempts çıktısı)
    const p1State = filterStateForPlayer({
      state,
      playerUid: 'p1',
      opponentUid: 'p2',
      opponentName: 'Rakip',
      opponentConnected: true,
      serverNowMs: 2100,
    });

    const p2State = filterStateForPlayer({
      state,
      playerUid: 'p2',
      opponentUid: 'p1',
      opponentName: 'Yazan',
      opponentConnected: true,
      serverNowMs: 2100,
    });

    // Her iki oyuncunun ekranında da balon metni ana cevap "Beşiktaş" olmalıdır
    expect(p1State.attempts).toHaveLength(1);
    expect(p1State.attempts[0].text).toBe('Beşiktaş');
    expect(p1State.attempts[0].mine).toBe(true);

    expect(p2State.attempts).toHaveLength(1);
    expect(p2State.attempts[0].text).toBe('Beşiktaş');
    expect(p2State.attempts[0].mine).toBe(false);
  });

  it('2. Yanlış (wrong) cevapta displayText atanmaz ve balonda kullanıcının yazdığı metin kalır', () => {
    let { state } = MatchEngine.start({
      config,
      playerIds: ['p1', 'p2'],
      questions: [sampleQuestion],
      nowMs: 1000,
      questionOrder: ['q_teams'],
    });

    const res = MatchEngine.submit({
      state,
      playerId: 'p1',
      rawInput: 'tamamen_yanlis',
      nowMs: 2000,
    });

    state = res.state;
    expect(state.currentRoundAttempts).toHaveLength(1);
    const attempt = state.currentRoundAttempts[0];
    expect(attempt.rawInput).toBe('tamamen_yanlis');
    expect(attempt.displayText).toBeUndefined();
    expect(attempt.resultType).toBe('wrong');

    const p1State = filterStateForPlayer({
      state,
      playerUid: 'p1',
      opponentUid: 'p2',
      opponentName: 'Rakip',
      opponentConnected: true,
      serverNowMs: 2100,
    });

    expect(p1State.attempts).toHaveLength(1);
    expect(p1State.attempts[0].text).toBe('tamamen_yanlis');
    expect(p1State.attempts[0].result).toBe('wrong');
  });

  it('3. Alias ile kabul edilen cevap sonradan ana cevapla veya başka aliasla tekrar girilirse repeated olur ve balona eklenmez', () => {
    let { state } = MatchEngine.start({
      config,
      playerIds: ['p1', 'p2'],
      questions: [sampleQuestion],
      nowMs: 1000,
      questionOrder: ['q_teams'],
    });

    // 1. p1 alias 'bjk' girer (doğru kabul edilir)
    let res = MatchEngine.submit({
      state,
      playerId: 'p1',
      rawInput: 'bjk',
      nowMs: 2000,
    });
    state = res.state;
    expect(state.turnPlayerId).toBe('p2');

    // 2. Sıra p2'ye geçti. p2 ana cevap 'Beşiktaş' yazar
    res = MatchEngine.submit({
      state,
      playerId: 'p2',
      rawInput: 'Beşiktaş',
      nowMs: 3000,
    });
    state = res.state;

    // AlreadySaid olayı döner
    expect(res.events).toHaveLength(1);
    expect(res.events[0].type).toBe('AlreadySaid');

    // Ham kayıtta 2 deneme vardır
    expect(state.currentRoundAttempts).toHaveLength(2);
    expect(state.currentRoundAttempts[1].resultType).toBe('repeated');

    // Ancak aktif tur görünümünde repeated elenir, sadece ilk doğru cevap (Beşiktaş) kalır
    const p2State = filterStateForPlayer({
      state,
      playerUid: 'p2',
      opponentUid: 'p1',
      opponentName: 'P1',
      opponentConnected: true,
      serverNowMs: 3100,
    });

    expect(p2State.attempts).toHaveLength(1);
    expect(p2State.attempts[0].text).toBe('Beşiktaş');
  });

  it('4. buildFinalMessage içinde doğru cevapların text alanı ana cevabı (displayText) taşır', () => {
    let { state } = MatchEngine.start({
      config,
      playerIds: ['p1', 'p2'],
      questions: [sampleQuestion],
      nowMs: 1000,
      questionOrder: ['q_teams'],
    });

    // p1 alias 'gs' girer
    const res = MatchEngine.submit({
      state,
      playerId: 'p1',
      rawInput: 'gs',
      nowMs: 2000,
    });
    state = res.state;

    // Turu bitirmek için roundHistory'ye ekleyelim
    const finalMsg = buildFinalMessage({
      state: {
        ...state,
        roundHistory: [
          {
            questionId: 'q_teams',
            starterPlayerId: 'p1',
            attempts: state.currentRoundAttempts,
            winnerId: 'p1',
            reason: 'timeout',
          },
        ],
      },
      playerUid: 'p1',
      opponentUid: 'p2',
    });

    expect(finalMsg.rounds).toHaveLength(1);
    expect(finalMsg.rounds[0].attempts).toHaveLength(1);
    expect(finalMsg.rounds[0].attempts[0].text).toBe('Galatasaray');
  });
});
