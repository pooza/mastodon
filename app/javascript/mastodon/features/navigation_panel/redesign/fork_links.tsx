import { useEffect, useState } from 'react';

import forkClasses from './fork_links.module.scss';
import { ListSection } from './list_section';
import classes from './navigation_link.module.scss';

// フォーク改変（#991）: `public/links.json` のリンク群をナビに出す。
// 旧 UI（`navigation_panel/index.tsx`）では区切り線＋見出しで並べていたが、
// 新 UI では各グループを「Custom Feeds」と同じ折りたためる `ListSection` にする。
// アイコンは Material Symbols のアイコン名（#954 で Google Fonts から読む）。

interface LinkItem {
  body: string;
  href: string;
  target?: string;
  icon?: string;
}

interface LinkGroup {
  body?: string;
  links: LinkItem[];
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null;

const isLinkItem = (value: unknown): value is LinkItem =>
  isObject(value) && 'href' in value;

// links.json はリンクの配列（見出しなし 1 グループ）か、
// グループ（`{ body, links }` またはリンクの配列）の配列を受け付ける。
const toLinkGroups = (data: unknown): LinkGroup[] => {
  if (!Array.isArray(data)) return [];

  const groups = data as unknown[];

  if (groups.every(isLinkItem)) {
    return [{ links: groups }];
  }

  return groups
    .map((group): LinkGroup | null => {
      if (Array.isArray(group)) {
        return { links: (group as unknown[]).filter(isLinkItem) };
      }

      if (isObject(group) && Array.isArray(group.links)) {
        const body = typeof group.body === 'string' ? group.body : undefined;
        return { body, links: (group.links as unknown[]).filter(isLinkItem) };
      }

      return null;
    })
    .filter((group): group is LinkGroup => group !== null);
};

const useLinkGroups = () => {
  const [linkGroups, setLinkGroups] = useState<LinkGroup[]>([]);

  useEffect(() => {
    const controller = new AbortController();

    void (async () => {
      try {
        const res = await fetch('/links.json', {
          credentials: 'same-origin',
          signal: controller.signal,
        });
        if (!res.ok) return;
        const data: unknown = await res.json();
        setLinkGroups(toLinkGroups(data));
      } catch {
        // links.json が無い・壊れているときはリンク群を出さない。
      }
    })();

    return () => {
      controller.abort();
    };
  }, []);

  return linkGroups;
};

const ExternalNavigationLink: React.FC<{ link: LinkItem }> = ({ link }) => (
  <li className={classes.wrapper}>
    <a
      href={link.href}
      target={link.target ?? '_blank'}
      rel='noopener'
      className={classes.link}
    >
      {link.icon && (
        <span className={classes.icon}>
          <span
            className={`material-symbols-outlined ${forkClasses.symbol}`}
            aria-hidden
          >
            {link.icon}
          </span>
        </span>
      )}
      <span className={classes.label}>{link.body}</span>
    </a>
  </li>
);

export const ForkLinkSections: React.FC = () => {
  const linkGroups = useLinkGroups();

  return linkGroups.map((group, gi) => (
    <ListSection
      // 開閉状態は見出しごとに保存する（グループの並べ替えに追従させる）。
      key={`${gi}-${group.body ?? ''}`}
      id={`fork-links-${group.body ?? gi}`}
      title={group.body ?? ''}
    >
      {group.links.map((link, li) => (
        <ExternalNavigationLink key={`${li}-${link.href}`} link={link} />
      ))}
    </ListSection>
  ));
};
