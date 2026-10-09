import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  MatchEngine,
  type EngineResult,
  type MatchConfig,
  type MatchState,
  type Question,
} from '../../src/engine';

interface ScenarioStep {
  readonly stepIndex: number;
  readonly action: 'submit' | 'tick' | 'forfeit' | 'startNextRound';
  readonly payload: Record<string, unknown>;
  readonly expectedEvents: readonly Record<string, unknown>[];
  readonly expectedStateSnapshot: {
    readonly phase: string;
    readonly turnPlayerId: string | null;
    readonly scores: Record<string, number>;
    readonly decisiveRounds: number;
    readonly totalRoundsPlayed: number;
    readonly currentQuestionId: string | null;
    readonly winnerId: string | null;
    readonly endedBy: string | null;
    readonly usedAnswerIds: readonly string[];
    readonly remainingNearMisses: Record<string, number>;
    readonly attemptsCount: number;
    readonly deadlineMs: number;
  };
}

interface Scenario {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly config: MatchConfig;
  readonly playerIds: readonly [string, string];
  readonly questionOrder: readonly string[];
  readonly initialNowMs: number;
  readonly steps: readonly ScenarioStep[];
}

interface ScenariosVector {
  readonly version: number;
  readonly totalScenarios: number;
  readonly scenarios: readonly Scenario[];
}

function loadVector(): ScenariosVector {
  const candidates = [
    path.resolve(process.cwd(), '../shared/test-vectors/engine_scenarios.json'),
    path.resolve(process.cwd(), 'shared/test-vectors/engine_scenarios.json'),
    path.resolve(__dirname, '../../../shared/test-vectors/engine_scenarios.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) {
      return JSON.parse(fs.readFileSync(p, 'utf-8')) as ScenariosVector;
    }
  }
  throw new Error('engine_scenarios.json bulunamadı');
}

const SAMPLE_QUESTIONS: Question[] = [
  {
    id: 'q1',
    categoryId: 'c1',
    text: 'Araba Markaları',
    answers: [
      { id: 'audi', display: 'Audi', aliases: ['audi', 'aude'] },
      { id: 'bmw', display: 'BMW', aliases: ['bmw'] },
      { id: 'mercedes', display: 'Mercedes', aliases: ['mercedes', 'merco'] },
      { id: 'toyota', display: 'Toyota', aliases: ['toyota'] },
      { id: 'honda', display: 'Honda', aliases: ['honda'] },
      { id: 'ford', display: 'Ford', aliases: ['ford'] },
    ],
  },
  {
    id: 'q2',
    categoryId: 'c2',
    text: 'Meyveler',
    answers: [
      { id: 'elma', display: 'Elma', aliases: ['elma'] },
      { id: 'armut', display: 'Armut', aliases: ['armut'] },
      { id: 'muz', display: 'Muz', aliases: ['muz'] },
      { id: 'cilek', display: 'Çilek', aliases: ['cilek'] },
      { id: 'portakal', display: 'Portakal', aliases: ['portakal'] },
      { id: 'karpuz', display: 'Karpuz', aliases: ['karpuz'] },
    ],
  },
  {
    id: 'q3',
    categoryId: 'c3',
    text: 'Başkentler',
    answers: [
      { id: 'ankara', display: 'Ankara', aliases: ['ankara'] },
      { id: 'paris', display: 'Paris', aliases: ['paris'] },
      { id: 'berlin', display: 'Berlin', aliases: ['berlin'] },
      { id: 'roma', display: 'Roma', aliases: ['roma'] },
      { id: 'madrid', display: 'Madrid', aliases: ['madrid'] },
      { id: 'tokyo', display: 'Tokyo', aliases: ['tokyo'] },
    ],
  },
  {
    id: 'q_small',
    categoryId: 'c_small',
    text: 'İki Seçenek',
    answers: [
      { id: 'evet', display: 'Evet', aliases: ['evet'] },
      { id: 'hayir', display: 'Hayır', aliases: ['hayir'] },
    ],
  },
];

describe('MatchEngine (shared test scenarios)', () => {
  const vector = loadVector();

  it('versiyon 1 olmalı ve en az 25 senaryo içermeli', () => {
    expect(vector.version).toBe(1);
    expect(vector.scenarios.length).toBeGreaterThanOrEqual(25);
  });

  for (const scen of vector.scenarios) {
    it(`[${scen.id}] ${scen.name}`, () => {
      let res: EngineResult = MatchEngine.start({
        config: scen.config,
        playerIds: scen.playerIds,
        questions: SAMPLE_QUESTIONS,
        nowMs: scen.initialNowMs,
        questionOrder: scen.questionOrder,
      });

      let state: MatchState = res.state;

      for (const step of scen.steps) {
        switch (step.action) {
          case 'submit':
            res = MatchEngine.submit({
              state,
              playerId: step.payload.playerId as string,
              rawInput: step.payload.rawInput as string,
              nowMs: step.payload.nowMs as number,
              questionsPool: SAMPLE_QUESTIONS,
            });
            break;

          case 'tick':
            res = MatchEngine.checkTimeout({
              state,
              nowMs: step.payload.nowMs as number,
            });
            break;

          case 'forfeit':
            res = MatchEngine.forfeit({
              state,
              playerId: step.payload.playerId as string,
              nowMs: step.payload.nowMs as number,
            });
            break;

          case 'startNextRound':
            res = MatchEngine.startNextRound({
              state,
              questions: SAMPLE_QUESTIONS,
              nowMs: step.payload.nowMs as number,
              questionOrder: scen.questionOrder,
            });
            break;
        }

        state = res.state;

        // Olaylar (events) karşılaştırması
        expect(res.events).toEqual(step.expectedEvents);

        // Durum anlık görüntüsü (state snapshot) karşılaştırması
        const expSnap = step.expectedStateSnapshot;
        expect(state.phase).toBe(expSnap.phase);
        expect(state.turnPlayerId).toBe(expSnap.turnPlayerId);
        expect(state.scores).toEqual(expSnap.scores);
        expect(state.decisiveRounds).toBe(expSnap.decisiveRounds);
        expect(state.totalRoundsPlayed).toBe(expSnap.totalRoundsPlayed);
        expect(state.currentQuestion?.id ?? null).toBe(expSnap.currentQuestionId);
        expect(state.winnerId).toBe(expSnap.winnerId);
        expect(state.endedBy).toBe(expSnap.endedBy);
        expect([...state.usedAnswerIds].sort()).toEqual([...expSnap.usedAnswerIds].sort());
        expect(state.remainingNearMisses).toEqual(expSnap.remainingNearMisses);
        expect(state.currentRoundAttempts.length).toBe(expSnap.attemptsCount);
        expect(state.deadlineMs).toBe(expSnap.deadlineMs);
      }
    });
  }
});

