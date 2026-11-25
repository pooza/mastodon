import { Fragment, useEffect, useState } from 'react';

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

const isOptionalString = (value: unknown) =>
  value === undefined || typeof value === 'string';

// 形式の判定用（href を持つものをリンクとみなす）。
const looksLikeLink = (value: unknown) => isObject(value) && 'href' in value;

// 描画するフィールドがすべて文字列のものだけを受け付ける。壊れた項目は
// その項目だけ落とし、ナビ全体の描画を巻き込まない（#999 の Codex 指摘）。
const isLinkItem = (value: unknown): value is LinkItem =>
  isObject(value) &&
  typeof value.href === 'string' &&
  typeof value.body === 'string' &&
  isOptionalString(value.icon) &&
  isOptionalString(value.target);

// links.json はリンクの配列（見出しなし 1 グループ）か、
// グループ（`{ body, links }` またはリンクの配列）の配列を受け付ける。
export const toLinkGroups = (data: unknown): LinkGroup[] => {
  if (!Array.isArray(data)) return [];

  const groups = data as unknown[];

  if (groups.every(looksLikeLink)) {
    return [{ links: groups.filter(isLinkItem) }];
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

  return linkGroups.map((group, gi) => {
    const links = group.links.map((link, li) => (
      <ExternalNavigationLink key={`${li}-${link.href}`} link={link} />
    ));

    // 見出しの無いグループは区画（折りたたみボタン）にせず、リンクをそのまま
    // 並べる。空の見出しと名前の無いボタンを出さない（#999 の Codex 指摘）。
    if (!group.body) {
      return <Fragment key={`${gi}-`}>{links}</Fragment>;
    }

    return (
      <ListSection
        // 開閉状態は見出しごとに保存する（グループの並べ替えに追従させる）。
        key={`${gi}-${group.body}`}
        id={`fork-links-${group.body}`}
        title={group.body}
      >
        {links}
      </ListSection>
    );
  });
};
