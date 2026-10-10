import { describe, expect, it } from 'vitest';
import {
  deserializeMatchState,
  serializeMatchState,
} from '../src/storage';
import {
  MatchEngine,
  type MatchConfig,
  type Question,
} from '../src/engine';

describe('MatchState Storage Serialization Round-Trip', () => {
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

  it('MatchState serileştirilip geri çözüldüğünde tüm alanları birebir korur', () => {
    const startRes = MatchEngine.start({
      config,
      playerIds: ['p1', 'p2'],
      questions: [sampleQuestion],
      nowMs: 1000,
      questionOrder: ['q1'],
    });

    const submitRes = MatchEngine.submit({
      state: startRes.state,
      playerId: 'p1',
      rawInput: 'elma',
      nowMs: 3000,
      questionsPool: [sampleQuestion],
    });

    const originalState = submitRes.state;

    // Serileştir
    const serialized = serializeMatchState(originalState);
    expect(Array.isArray(serialized.usedAnswerIds)).toBe(true);
    expect(Array.isArray(serialized.usedQuestionIds)).toBe(true);

    // Geri dönüştür
    const deserialized = deserializeMatchState(serialized);

    expect(deserialized.phase).toBe(originalState.phase);
    expect(deserialized.turnPlayerId).toBe(originalState.turnPlayerId);
    expect(deserialized.scores).toEqual(originalState.scores);
    expect(deserialized.decisiveRounds).toBe(originalState.decisiveRounds);
    expect(deserialized.totalRoundsPlayed).toBe(originalState.totalRoundsPlayed);
    expect(deserialized.currentQuestion).toEqual(originalState.currentQuestion);
    expect(deserialized.winnerId).toBe(originalState.winnerId);
    expect(deserialized.endedBy).toBe(originalState.endedBy);
    expect(deserialized.questionOrder).toEqual(originalState.questionOrder);

    // Set'lerin düzgün çözüldüğünü doğrula
    expect(deserialized.usedAnswerIds instanceof Set).toBe(true);
    expect([...deserialized.usedAnswerIds]).toEqual([...originalState.usedAnswerIds]);

    expect(deserialized.usedQuestionIds instanceof Set).toBe(true);
    expect([...deserialized.usedQuestionIds]).toEqual([...originalState.usedQuestionIds]);

    expect(deserialized.currentRoundAttempts).toEqual(originalState.currentRoundAttempts);
    expect(deserialized.roundHistory).toEqual(originalState.roundHistory);
    expect(deserialized.remainingNearMisses).toEqual(originalState.remainingNearMisses);
  });
});

