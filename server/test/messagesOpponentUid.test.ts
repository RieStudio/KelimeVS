import { describe, expect, it, vi } from 'vitest';
import { buildFinalMessage } from '../src/storage';
import type { MatchState } from '../src/storage';

describe('Messages opponentUid Protocol Tests', () => {
  const dummyState: MatchState = {
    matchId: 'm_normal_123',
    currentRoundNumber: 3,
    scores: { p1: 2, p2: 1 },
    winnerId: 'p1',
    endedBy: 'normal',
    roundHistory: [],
  };

  it('1. Gerçek oyuncu maçında buildFinalMessage yanıtında opponentUid yer alır', () => {
    const finalMsg = buildFinalMessage({
      state: dummyState,
      playerUid: 'p1',
      opponentUid: 'p2',
      opponentName: 'PlayerTwo',
      opponentFrame: 'vine',
      coinsAwarded: 30,
      coins: 130,
    });

    expect(finalMsg.t).toBe('final');
    expect(finalMsg.opponentUid).toBe('p2');
    expect(finalMsg.opponentName).toBe('PlayerTwo');
    expect(finalMsg.opponentFrame).toBe('vine');
  });

  it('2. Bot maçında (opponentUid "bot" veya "bot_" veya matchId "bot_") opponentUid ASLA gönderilmez (undefined)', () => {
    // 2.a opponentUid === 'bot'
    const msg1 = buildFinalMessage({
      state: dummyState,
      playerUid: 'p1',
      opponentUid: 'bot',
      opponentName: 'KelimeBot',
    });
    expect(msg1.opponentUid).toBeUndefined();
    expect('opponentUid' in msg1).toBe(false);

    // 2.b opponentUid starts with 'bot_'
    const msg2 = buildFinalMessage({
      state: dummyState,
      playerUid: 'p1',
      opponentUid: 'bot_easy_01',
      opponentName: 'BotEasy',
    });
    expect(msg2.opponentUid).toBeUndefined();
    expect('opponentUid' in msg2).toBe(false);

    // 2.c state.matchId starts with 'bot_'
    const botMatchState: MatchState = {
      ...dummyState,
      matchId: 'bot_match_999',
    };
    const msg3 = buildFinalMessage({
      state: botMatchState,
      playerUid: 'p1',
      opponentUid: 'some_bot_id',
      opponentName: 'BotMedium',
    });
    expect(msg3.opponentUid).toBeUndefined();
    expect('opponentUid' in msg3).toBe(false);
  });
});
