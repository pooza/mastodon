// モロヘイヤ（mulukhiya-toot-proxy）の番組表エントリが持つ放送日時を、実況
// タグセットのドロップダウンに出す 1 つの文字列へ畳む（#953）。
//
// 表示の書式は capsicum（`program_schedule_display.dart`）に合わせてある。
// 3 クライアント（capsicum / ダイスキー / ここ）で書式が割れると番組表を
// 見比べるときに困るため、片方だけ変えないこと。

const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const TIME_PATTERN = /^(\d{1,2}):(\d{2})$/;

// `next_on`（次回放送日, `YYYY-MM-DD`）をローカル日付としてパースする。
//
// `new Date('2026-08-09')` は UTC 深夜として解釈されるので使わない。時差が
// 入ると「今日」が 1 日ズレる。書式も厳密に見る。素通しすると実在しない日
// （`2026-02-31`）が「それらしい別の日」として表示されてしまうため。
// `/mulukhiya/api/program` は `var/program.yaml` の値をそのまま載せるので、
// 手編集や外部データソース由来の不正値がここまで届く。
export const parseProgramNextOn = (value: unknown): Date | null => {
  if (typeof value !== 'string') return null;

  const matched = DATE_PATTERN.exec(value);
  if (!matched) return null;

  const year = Number(matched[1]);
  const month = Number(matched[2]);
  const day = Number(matched[3]);
  const date = new Date(year, month - 1, day);

  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  )
    return null;

  return date;
};

// `start_time`（放送開始時刻）をパースし `HH:MM` に正規化する。モロヘイヤは
// 保存時にゼロ埋めするが、古いエントリや手編集では `9:00` のまま残りうる。
export const parseProgramStartTime = (value: unknown): string | null => {
  if (typeof value !== 'string') return null;

  const matched = TIME_PATTERN.exec(value);
  if (!matched) return null;

  const hour = Number(matched[1]);
  const minute = Number(matched[2]);
  if (hour > 23 || minute > 59) return null;

  return `${String(hour).padStart(2, '0')}:${matched[2]}`;
};

// タグセットを選ぶのは実況の直前なので、当日・翌日だけ「今日」「明日」へ
// 置き換え、それ以遠は `M/d` にする。判定はローカル日付で行う。
//
// ⚠ `next_on` を持たない枠は日付を出さない。「毎日」とは書かないこと
//   （2026-08-16 判断。放送日を持たないことと毎日放送であることは違う）。
const formatDatePart = (nextOn: Date | null, now: Date): string => {
  if (!nextOn) return '';

  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const days = Math.round(
    (nextOn.getTime() - today.getTime()) / (24 * 60 * 60 * 1000),
  );

  if (days === 0) return '今日';
  if (days === 1) return '明日';

  return `${nextOn.getMonth() + 1}/${nextOn.getDate()}`;
};

// 日付が無く時刻だけある枠は時刻のみ（`22:00`）、どちらも無ければ空文字を
// 返す。呼び出し側は空文字なら要素ごと落とすこと。
export const programScheduleLabel = (
  nextOn: unknown,
  startTime: unknown,
  now: Date,
): string => {
  const datePart = formatDatePart(parseProgramNextOn(nextOn), now);
  const timePart = parseProgramStartTime(startTime);

  if (timePart === null) return datePart;
  if (datePart === '') return timePart;

  return `${datePart} ${timePart}`;
};
