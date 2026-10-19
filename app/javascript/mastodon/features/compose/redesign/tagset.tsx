import type React from 'react';
import { useCallback, useRef, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import {
  ArrowClockwiseIcon,
  FilmStripIcon,
  HashIcon,
  XCircleIcon,
} from '@phosphor-icons/react';

import { changeTagset } from '@/mastodon/actions/compose';
import { Button } from '@/mastodon/components/button/redesign';
import {
  Menu,
  MenuItem,
  MenuItemDivider,
  MenuList,
  MenuTrigger,
} from '@/mastodon/components/menu';
import { useAppDispatch, useAppSelector } from '@/mastodon/store';

import { localDayKey, programScheduleLabel } from '../util/program_schedule';

// 実況タグセット（#905）の新 UI 版（#989）。旧 UI の
// `components/tagset_dropdown.tsx` は `language_dropdown.tsx` のミラーだったが、
// 新 UI では `redesign/language.tsx` の `LanguageButton` と同じ並びに置き、
// 一覧は設定メニュー（`redesign/settings.tsx`）と同じ `Menu` 部品で組む。

const messages = defineMessages({
  empty_short: { id: 'tagset.empty.short', defaultMessage: 'Empty' },
  empty_long: { id: 'tagset.empty.long', defaultMessage: 'Empty tagset' },
  episodes_short: {
    id: 'tagset.episodes.short',
    defaultMessage: 'Other episodes',
  },
  episodes_long: {
    id: 'tagset.episodes.long',
    defaultMessage: 'Episode browser of Mulukhiya',
  },
  reload_short: { id: 'tagset.reload.short', defaultMessage: 'Reload' },
  reload_long: { id: 'tagset.reload.long', defaultMessage: 'Reload episodes' },
});

// モロヘイヤ（mulukhiya-toot-proxy）の番組表 API が返すエントリ。
interface ProgramEntry {
  enable?: boolean;
  series?: string;
  episode?: string | number;
  episode_suffix?: string;
  subtitle?: string;
  air?: boolean;
  livecure?: boolean;
  minutes?: number;
  extra_tags?: string[];
  // 次回放送日（`YYYY-MM-DD`）と放送開始時刻（`HH:MM`）。どちらもモロヘイヤが
  // 返すが、`next_on` を持たない枠がある（#953）。
  next_on?: string;
  start_time?: string;
}

type ProgramResponse = Record<string, ProgramEntry>;

interface ProgramOption {
  key: string;
  text: string;
  meta: string;
  // 選んだときに reducer へそのまま渡す（reducer では番組表を取り直さない）。
  entry: ProgramEntry;
}

export const TagsetButton: React.FC = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const isEditing = useAppSelector((state) => !!state.compose.get('id'));

  const [programs, setPrograms] = useState<ProgramOption[]>([]);
  // 選択肢を組み立てたときのローカル日付。「今日」「明日」を含むラベルは
  // 日付をまたぐと嘘になるので、開き直したときの作り直し判定に使う。
  const loadedDayRef = useRef<string | null>(null);

  // モロヘイヤから番組表を取得し、タグセットの選択肢を組み立てる。
  // 取得前に program/update を叩いて番組表を最新化するのは旧実装と同じ挙動。
  const loadPrograms = useCallback(async () => {
    const now = new Date();
    loadedDayRef.current = localDayKey(now);

    const items: ProgramOption[] = [];

    try {
      await fetch('/mulukhiya/api/program/update', { method: 'POST' });
      const response = await fetch('/mulukhiya/api/program');
      const result = (await response.json()) as ProgramResponse;

      for (const [key, entry] of Object.entries(result)) {
        if (!entry.enable) continue;

        const meta: string[] = [];
        // 放送日時を meta の先頭に置く（#953）。API のレスポンスは既に放送順
        // なので、日付が出れば「どれが今日の枠か」が一覧で分かる。
        // `next_on` を持たない枠では空になるので、その場合は足さない。
        const schedule = programScheduleLabel(
          entry.next_on,
          entry.start_time,
          now,
        );
        if (schedule) meta.push(schedule);
        if (entry.episode)
          meta.push(`${entry.episode}${entry.episode_suffix ?? '話'}`);
        if (entry.subtitle) meta.push(`「${entry.subtitle}」`);
        if (entry.air) meta.push('エア番組');
        if (entry.livecure) meta.push('実況');
        if (entry.minutes) meta.push(`(${entry.minutes}分)`);
        for (const tag of entry.extra_tags ?? []) meta.push(tag);

        items.push({
          key,
          text: `「${entry.series ?? ''}」用タグセット`,
          meta: meta.join(' '),
          entry,
        });
      }
    } catch {
      // モロヘイヤ未接続時は番組リストなしで継続する。
    }

    setPrograms(items);
  }, []);

  // 初回オープン時にモロヘイヤから番組表を取得する（マウントごとの
  // program/update を避けるため effect ではなく開いた時に遅延ロード）。
  //
  // 日付をまたいで開き直したときも取り直す。組み立て済みのラベルは
  // 「今日」「明日」を持つので、日が変わるとそのまま 1 日ズレて嘘になる（#953）。
  const handleOpen = useCallback(() => {
    if (
      loadedDayRef.current === null ||
      loadedDayRef.current !== localDayKey(new Date())
    )
      void loadPrograms();
  }, [loadPrograms]);

  const handleSelect = useCallback(
    (value: string) => {
      if (value === 'episodes') {
        window.open('/mulukhiya/app/episode');
        return;
      }
      if (value === 'empty') {
        dispatch(changeTagset(value));
        return;
      }
      const program = programs.find((p) => p.key === value);
      if (program) dispatch(changeTagset(value, program.entry));
    },
    [dispatch, programs],
  );

  const handleReload = useCallback(() => {
    void loadPrograms();
  }, [loadPrograms]);

  return (
    <Menu onOpen={handleOpen}>
      <MenuTrigger
        as={Button}
        size='sm'
        leadingIcon={HashIcon}
        disabled={isEditing}
        tooltip={{
          type: 'description',
          text: (
            <FormattedMessage
              id='tagset.change'
              defaultMessage='Change tagset'
            />
          ),
        }}
      >
        <FormattedMessage id='tagset.label' defaultMessage='Livecure' />
      </MenuTrigger>

      <MenuList maxWidth={320} placement='bottom-end' strategy='fixed'>
        <TagsetMenuItem
          value='empty'
          icon={XCircleIcon}
          description={intl.formatMessage(messages.empty_long)}
          onSelect={handleSelect}
        >
          {intl.formatMessage(messages.empty_short)}
        </TagsetMenuItem>

        {programs.map((program) => (
          <TagsetMenuItem
            key={program.key}
            value={program.key}
            icon={HashIcon}
            description={program.meta}
            onSelect={handleSelect}
          >
            {program.text}
          </TagsetMenuItem>
        ))}

        <MenuItemDivider />

        <TagsetMenuItem
          value='episodes'
          icon={FilmStripIcon}
          description={intl.formatMessage(messages.episodes_long)}
          onSelect={handleSelect}
        >
          {intl.formatMessage(messages.episodes_short)}
        </TagsetMenuItem>

        <MenuItem
          icon={ArrowClockwiseIcon}
          description={intl.formatMessage(messages.reload_long)}
          keepMenuOpenOnClick
          onClick={handleReload}
        >
          {intl.formatMessage(messages.reload_short)}
        </MenuItem>
      </MenuList>
    </Menu>
  );
};

const TagsetMenuItem: React.FC<{
  value: string;
  icon: React.ComponentProps<typeof MenuItem>['icon'];
  description: React.ReactNode;
  onSelect: (value: string) => void;
  children: React.ReactNode;
}> = ({ value, icon, description, onSelect, children }) => {
  const handleClick = useCallback(() => {
    onSelect(value);
  }, [onSelect, value]);

  return (
    <MenuItem icon={icon} description={description} onClick={handleClick}>
      {children}
    </MenuItem>
  );
};
