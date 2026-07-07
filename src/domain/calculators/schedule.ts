/**
 * 6-club round-robin schedule.
 * Turno: 5 rounds; Returno: same fixtures with reversed home/away.
 * Total: 10 rounds, 30 matches, 3 matches per round, 1 match per club per round.
 *
 * Uses the exact fixture list from the BagreFut spec, mapped from
 * label indexes A..F to caller-provided clubIds.
 */

export interface ScheduledMatch {
  round: number;
  home: string;
  away: string;
}

// Labels A..F correspond to positions [0..5] in the input clubIds array.
const TURNO_ROUNDS: Array<Array<[string, string]>> = [
  [["A","F"], ["B","E"], ["C","D"]],           // round 1
  [["F","D"], ["E","C"], ["A","B"]],           // round 2
  [["B","F"], ["C","A"], ["D","E"]],           // round 3
  [["F","E"], ["A","D"], ["B","C"]],           // round 4
  [["C","F"], ["D","B"], ["E","A"]],           // round 5
];

const RETURNO_ROUNDS: Array<Array<[string, string]>> = [
  [["F","A"], ["E","B"], ["D","C"]],           // round 6
  [["D","F"], ["C","E"], ["B","A"]],           // round 7
  [["F","B"], ["A","C"], ["E","D"]],           // round 8
  [["E","F"], ["D","A"], ["C","B"]],           // round 9
  [["F","C"], ["B","D"], ["A","E"]],           // round 10
];

const LABELS = ["A","B","C","D","E","F"] as const;

/**
 * @param clubIds exactly 6 ids in a stable order (A..F).
 * @returns 30 scheduled matches across 10 rounds.
 */
export function generateSchedule(clubIds: readonly string[]): ScheduledMatch[] {
  if (clubIds.length !== 6) {
    throw new Error("generateSchedule requires exactly 6 clubs");
  }
  const map = Object.fromEntries(LABELS.map((l, i) => [l, clubIds[i]])) as Record<string, string>;
  const rounds = [...TURNO_ROUNDS, ...RETURNO_ROUNDS];
  const result: ScheduledMatch[] = [];
  rounds.forEach((round, idx) => {
    for (const [h, a] of round) {
      result.push({ round: idx + 1, home: map[h], away: map[a] });
    }
  });
  return result;
}
