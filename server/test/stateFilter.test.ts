import { describe, expect, it } from 'vitest';
import { filterStateForPlayer } from '../src/storage';
import {
  MatchEngine,
  type MatchConfig,
  type Question,
} from '../src/engine';

describe('Player-Specific State Filtering & Near-Miss Secrecy', () => {
  const sampleQuestion: Question = {
    id: 'q1',
    categoryId: 'c1',
    text: 'Meyveler',
    answers: [
      { id: 'elma', display: 'Elma', aliases: ['elma'] },
      { id: 'armut', display: 'Armut', aliases: ['armut'] },
    ],
  };

  const config: MatchConfig = {
    roundsToWin: 2,
    answerSeconds: 15,
    graceMs: 0,
    nearMissPerRound: 1,
    minAnswersPerQuestion: 0,
    minSubmitIntervalMs: 600,
    maxAttemptsPerTurn: 25,
  };

  it('aktif turda ipucu verilen yakın deneme her iki oyuncuya da gizlidir', () => {
    const startRes = MatchEngine.start({
      config,
      playerIds: ['p1', 'p2'],
      questions: [sampleQuestion],
      nowMs: 1000,
      questionOrder: ['q1'],
    });

    // p1 yakın deneme yapar (elam -> NearMiss)
    const submitRes = MatchEngine.submit({
      state: startRes.state,
      playerId: 'p1',
      rawInput: 'elam',
      nowMs: 2000,
      questionsPool: [sampleQuestion],
    });

    const stateP1 = filterStateForPlayer({
      state: submitRes.state,
      playerUid: 'p1',
      opponentUid: 'p2',
      opponentName: 'Bob',
      opponentConnected: true,
      serverNowMs: 2500,
    });

    const stateP2 = filterStateForPlayer({
      state: submitRes.state,
      playerUid: 'p2',
      opponentUid: 'p1',
      opponentName: 'Alice',
      opponentConnected: true,
      serverNowMs: 2500,
    });

    // İpucu verilen yakın deneme aktif turda hiç kimseye balon olarak gitmez
    expect(stateP1.attempts.length).toBe(0);
    expect(stateP2.attempts.length).toBe(0);
  });

  it('aktif turda kotası bitmiş yakın deneme sahibine görünür ama rakibe ASLA gitmez', () => {
    // quota: 0 olan config
    const noQuotaConfig: MatchConfig = {
      ...config,
      nearMissPerRound: 0,
    };

    const startRes = MatchEngine.start({
      config: noQuotaConfig,
      playerIds: ['p1', 'p2'],
      questions: [sampleQuestion],
      nowMs: 1000,
      questionOrder: ['q1'],
    });

    // p1 yakın deneme yapar (elam -> WrongAnswer, isClose=true, hintShown=false)
    const submitRes = MatchEngine.submit({
      state: startRes.state,
      playerId: 'p1',
      rawInput: 'elam',
      nowMs: 2000,
      questionsPool: [sampleQuestion],
    });

    const stateP1 = filterStateForPlayer({
      state: submitRes.state,
      playerUid: 'p1',
      opponentUid: 'p2',
      opponentName: 'Bob',
      opponentConnected: true,
      serverNowMs: 2500,
    });

    const stateP2 = filterStateForPlayer({
      state: submitRes.state,
      playerUid: 'p2',
      opponentUid: 'p1',
      opponentName: 'Alice',
      opponentConnected: true,
      serverNowMs: 2500,
    });

    // Sahibi (p1) görür
    expect(stateP1.attempts.length).toBe(1);
    expect(stateP1.attempts[0].mine).toBe(true);
    expect(stateP1.attempts[0].text).toBe('elam');

    // Rakip (p2) ASLA görmez (kopya çekilmesin diye)
    expect(stateP2.attempts.length).toBe(0);
  });

  it('normal yanlış deneme her iki oyuncuya da görünür', () => {
    const startRes = MatchEngine.start({
      config,
      playerIds: ['p1', 'p2'],
      questions: [sampleQuestion],
      nowMs: 1000,
      questionOrder: ['q1'],
    });

    // p1 tamamen alakasız bir kelime yazar
    const submitRes = MatchEngine.submit({
      state: startRes.state,
      playerId: 'p1',
      rawInput: 'kelimego',
      nowMs: 2000,
      questionsPool: [sampleQuestion],
    });

    const stateP1 = filterStateForPlayer({
      state: submitRes.state,
      playerUid: 'p1',
      opponentUid: 'p2',
      opponentName: 'Bob',
      opponentConnected: true,
      serverNowMs: 2500,
    });

    const stateP2 = filterStateForPlayer({
      state: submitRes.state,
      playerUid: 'p2',
      opponentUid: 'p1',
      opponentName: 'Alice',
      opponentConnected: true,
      serverNowMs: 2500,
    });

    expect(stateP1.attempts.length).toBe(1);
    expect(stateP1.attempts[0].mine).toBe(true);

    expect(stateP2.attempts.length).toBe(1);
    expect(stateP2.attempts[0].mine).toBe(false);
  });

  it('tur bittiğinde tüm denemeler herkese görünür', () => {
    const noQuotaConfig: MatchConfig = {
      ...config,
      nearMissPerRound: 0,
    };

    const startRes = MatchEngine.start({
      config: noQuotaConfig,
      playerIds: ['p1', 'p2'],
      questions: [sampleQuestion],
      nowMs: 1000,
      questionOrder: ['q1'],
    });

    // p1 yakın deneme yapar
    const s1 = MatchEngine.submit({
      state: startRes.state,
      playerId: 'p1',
      rawInput: 'elam',
      nowMs: 2000,
      questionsPool: [sampleQuestion],
    });

    // p1 timeout olur -> tur biter
    const timeoutRes = MatchEngine.checkTimeout({
      state: s1.state,
      nowMs: 20000,
    });

    expect(timeoutRes.state.phase).toBe('roundEnded');

    const stateP2 = filterStateForPlayer({
      state: timeoutRes.state,
      playerUid: 'p2',
      opponentUid: 'p1',
      opponentName: 'Alice',
      opponentConnected: true,
      serverNowMs: 20500,
    });

    // Tur bitince p2 de p1'in yakın denemesini görebilir
    expect(stateP2.attempts.length).toBe(1);
    expect(stateP2.attempts[0].text).toBe('elam');
  });
});

