import { useCallback, useRef, useState } from 'react';

import { useIntl, defineMessages } from 'react-intl';

import classNames from 'classnames';

import { Popover } from '@/mastodon/components/popover';
import CancelIcon from '@/material-icons/400-24px/cancel.svg?react';
import MovieIcon from '@/material-icons/400-24px/movie.svg?react';
import RefreshIcon from '@/material-icons/400-24px/refresh.svg?react';
import TagIcon from '@/material-icons/400-24px/tag.svg?react';
import { changeTagset } from 'mastodon/actions/compose';
import type { SelectItem } from 'mastodon/components/dropdown_selector';
import { DropdownSelector } from 'mastodon/components/dropdown_selector';
import { Icon } from 'mastodon/components/icon';
import { useAppDispatch } from 'mastodon/store';

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
  change: { id: 'tagset.change', defaultMessage: 'Change tagset' },
  label: { id: 'tagset.label', defaultMessage: 'Livecure' },
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
}

type ProgramResponse = Record<string, ProgramEntry>;

export const TagsetDropdown: React.FC<{
  disabled?: boolean;
}> = ({ disabled }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();

  const [open, setOpen] = useState(false);
  const [options, setOptions] = useState<SelectItem[]>([]);
  const activeElementRef = useRef<HTMLElement | null>(null);
  const [targetElement, setTargetElement] = useState<HTMLElement | null>(null);

  // モロヘイヤから番組表を取得し、タグセットの選択肢を組み立てる。
  // 取得前に program/update を叩いて番組表を最新化するのは旧実装と同じ挙動。
  const loadOptions = useCallback(async () => {
    const items: SelectItem[] = [
      {
        value: 'empty',
        icon: 'cancel',
        iconComponent: CancelIcon,
        text: intl.formatMessage(messages.empty_short),
        meta: intl.formatMessage(messages.empty_long),
      },
    ];

    try {
      await fetch('/mulukhiya/api/program/update', { method: 'POST' });
      const response = await fetch('/mulukhiya/api/program');
      const result = (await response.json()) as ProgramResponse;

      for (const [key, entry] of Object.entries(result)) {
        if (!entry.enable) continue;

        const meta: string[] = [];
        if (entry.episode)
          meta.push(`${entry.episode}${entry.episode_suffix ?? '話'}`);
        if (entry.subtitle) meta.push(`「${entry.subtitle}」`);
        if (entry.air) meta.push('エア番組');
        if (entry.livecure) meta.push('実況');
        if (entry.minutes) meta.push(`(${entry.minutes}分)`);
        for (const tag of entry.extra_tags ?? []) meta.push(tag);

        items.push({
          value: key,
          icon: 'tag',
          iconComponent: TagIcon,
          text: `「${entry.series ?? ''}」用タグセット`,
          meta: meta.join(' '),
        });
      }
    } catch {
      // モロヘイヤ未接続時は番組リストなしで継続する。
    }

    items.push({
      value: 'episodes',
      icon: 'movie',
      iconComponent: MovieIcon,
      text: intl.formatMessage(messages.episodes_short),
      meta: intl.formatMessage(messages.episodes_long),
    });
    items.push({
      value: 'reload',
      icon: 'refresh',
      iconComponent: RefreshIcon,
      text: intl.formatMessage(messages.reload_short),
      meta: intl.formatMessage(messages.reload_long),
    });

    setOptions(items);
  }, [intl]);

  const handleMouseDown = useCallback(() => {
    if (!open && document.activeElement instanceof HTMLElement) {
      activeElementRef.current = document.activeElement;
    }
  }, [open]);

  const handleToggle = useCallback(() => {
    if (open && activeElementRef.current)
      activeElementRef.current.focus({ preventScroll: true });

    // 初回オープン時にモロヘイヤから番組表を取得する（マウントごとの
    // program/update を避けるため effect ではなく開いた時に遅延ロード）。
    if (!open && options.length === 0) void loadOptions();

    setOpen(!open);
  }, [open, options.length, loadOptions]);

  const handleClose = useCallback(() => {
    if (open && activeElementRef.current)
      activeElementRef.current.focus({ preventScroll: true });

    setOpen(false);
  }, [open]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Escape') handleClose();
    },
    [handleClose],
  );

  const handleChange = useCallback(
    (value: string) => {
      if (value === 'reload') {
        void loadOptions();
        return;
      }

      dispatch(changeTagset(value));
    },
    [dispatch, loadOptions],
  );

  return (
    <>
      <button
        type='button'
        ref={setTargetElement}
        title={intl.formatMessage(messages.change)}
        aria-expanded={open}
        onClick={handleToggle}
        onMouseDown={handleMouseDown}
        onKeyDown={handleKeyDown}
        disabled={disabled}
        className={classNames('dropdown-button', { active: open })}
      >
        <Icon id='tag' icon={TagIcon} />
        <span className='dropdown-button__label'>
          {intl.formatMessage(messages.label)}
        </span>
      </button>

      <Popover
        isOpen={open}
        onClose={handleClose}
        offset={5}
        reference={targetElement}
      >
        {({ props, placement }) => (
          <div {...props}>
            <div
              className={`dropdown-animation tagset-dropdown__dropdown ${placement}`}
            >
              <DropdownSelector
                items={options}
                value=''
                onClose={handleClose}
                onChange={handleChange}
              />
            </div>
          </div>
        )}
      </Popover>
    </>
  );
};
