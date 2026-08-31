import { describe, expect, it } from 'vitest';

import {
  parseProgramNextOn,
  parseProgramStartTime,
  programScheduleLabel,
} from './program_schedule';

// #953: 実況タグセットのドロップダウンに出す放送日時ラベル。
// 期待値は capsicum の `program_schedule_display_test.dart` と揃えてある。
describe('programScheduleLabel', () => {
  // 2026-08-09 (日) 12:00 を「今」として固定する。
  const now = new Date(2026, 7, 9, 12);

  it('当日は「今日」', () => {
    expect(programScheduleLabel('2026-08-09', '08:30', now)).toBe('今日 08:30');
  });

  it('翌日は「明日」', () => {
    expect(programScheduleLabel('2026-08-10', '20:00', now)).toBe('明日 20:00');
  });

  it('2 日以降は M/d', () => {
    expect(programScheduleLabel('2026-08-12', '19:30', now)).toBe('8/12 19:30');
  });

  it('年をまたいでも M/d のまま（番組表は先の予定を持たない）', () => {
    expect(programScheduleLabel('2027-01-03', '08:30', now)).toBe('1/3 08:30');
  });

  it('過去日も M/d で出す（更新されていない枠を隠さない）', () => {
    expect(programScheduleLabel('2026-08-02', '08:30', now)).toBe('8/2 08:30');
  });

  it('next_on が無い枠は日付を出さない', () => {
    // 「毎日」とは書かない。放送日を持たないことと毎日放送であることは違う。
    expect(programScheduleLabel(undefined, undefined, now)).toBe('');
    expect(programScheduleLabel(undefined, '22:00', now)).toBe('22:00');
  });

  it('日付が無いとき先頭に空白が残らない', () => {
    const label = programScheduleLabel(undefined, '22:00', now);

    expect(label).toBe(label.trim());
  });

  it('start_time だけ落ちても日付は出す', () => {
    expect(programScheduleLabel('2026-08-09', undefined, now)).toBe('今日');
  });

  it('「今日」の判定はローカル日付で行う（時刻の遠近に引きずられない）', () => {
    // 当日の 23:59 でも「今日」、翌日の 00:01 は「明日」。UTC 換算で判定すると
    // ここが 1 日ズレる。
    expect(
      programScheduleLabel('2026-08-09', '23:59', new Date(2026, 7, 9, 0, 1)),
    ).toBe('今日 23:59');
    expect(
      programScheduleLabel('2026-08-10', '00:01', new Date(2026, 7, 9, 23, 59)),
    ).toBe('明日 00:01');
  });

  it('パースできない値は日時を出さずに落とす', () => {
    expect(programScheduleLabel('2026/08/09', '08:30', now)).toBe('08:30');
    expect(programScheduleLabel('2026-08-09', '25:00', now)).toBe('今日');
    expect(programScheduleLabel(20260809, 830, now)).toBe('');
  });
});

describe('parseProgramNextOn', () => {
  it('YYYY-MM-DD をローカル日付として読む', () => {
    const date = parseProgramNextOn('2026-08-09');

    expect(date?.getFullYear()).toBe(2026);
    expect(date?.getMonth()).toBe(7);
    expect(date?.getDate()).toBe(9);
  });

  it('実在しない日をロールオーバーさせない', () => {
    // `new Date(2026, 1, 31)` は 3/3 になる。素通しすると番組表に無い日付が出る。
    expect(parseProgramNextOn('2026-02-31')).toBeNull();
  });

  it('書式違い・非文字列は null', () => {
    expect(parseProgramNextOn('2026-8-9')).toBeNull();
    expect(parseProgramNextOn('2026-08-09T00:00:00Z')).toBeNull();
    expect(parseProgramNextOn('')).toBeNull();
    expect(parseProgramNextOn(null)).toBeNull();
  });
});

describe('parseProgramStartTime', () => {
  it('ゼロ埋めされていない時刻を HH:MM へ正規化する', () => {
    expect(parseProgramStartTime('9:00')).toBe('09:00');
    expect(parseProgramStartTime('22:00')).toBe('22:00');
  });

  it('24 時間制の範囲外・書式違いは null', () => {
    expect(parseProgramStartTime('24:00')).toBeNull();
    expect(parseProgramStartTime('12:60')).toBeNull();
    expect(parseProgramStartTime('1230')).toBeNull();
    expect(parseProgramStartTime(undefined)).toBeNull();
  });
});
