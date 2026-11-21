/** 参考稿里用到的图标（内联 SVG） */
import type { ItemId } from '@host/core/data/items';

export const IconBack = () => (
  <svg viewBox="0 0 24 24">
    <path d="M15 5l-7 7 7 7" />
  </svg>
);

export const IconClose = () => (
  <svg viewBox="0 0 24 24">
    <path d="M6 6l12 12M18 6L6 18" />
  </svg>
);

export const IconMenu = () => (
  <svg viewBox="0 0 24 24">
    <path d="M4 6h16M8 12h12M4 18h16" />
  </svg>
);

export const IconChat = () => (
  <svg viewBox="0 0 24 24">
    <path d="M4 5h16v11H9l-5 4z" />
  </svg>
);

export const IconFlame = () => (
  <svg viewBox="0 0 24 24">
    <path d="M12 2c1 4 5.5 6 5.5 11.5a5.5 5.5 0 0 1-11 0c0-2.3 1-4 2.2-5 0 2.2 1 3.3 2.2 3.3C10.9 8.5 10 5.5 12 2z" />
  </svg>
);

export const IconCoin = () => (
  <svg viewBox="0 0 24 24">
    <path d="M12 2.5l8.2 4.75v9.5L12 21.5l-8.2-4.75v-9.5z" />
  </svg>
);

export const IconLock = () => (
  <svg viewBox="0 0 24 24">
    <rect x="5" y="11" width="14" height="10" rx="2" />
    <path d="M8 11V8a4 4 0 0 1 8 0v3" />
  </svg>
);

export function ItemIcon({ id }: { id: ItemId }) {
  switch (id) {
    case 'crit':
      return (
        <svg viewBox="0 0 24 24">
          <path d="M12 1.5l2.6 7.9 7.9 2.6-7.9 2.6L12 22.5l-2.6-7.9L1.5 12l7.9-2.6z" />
        </svg>
      );
    case 'dbl':
      return (
        <svg viewBox="0 0 24 24">
          <path d="M3.5 6.5l2-2 4 4 4-4 2 2-4 4 4 4-2 2-4-4-4 4-2-2 4-4z" />
          <path d="M15.5 13.5c0-2 1.3-3 3-3s3 1 3 2.6c0 1.6-1.3 2.4-3.4 4.4h3.6v2h-6.4v-1.7c3-2.8 3.9-3.5 3.9-4.6 0-.6-.4-.9-1-.9s-1 .4-1 1.2z" />
        </svg>
      );
    case 'shield':
      return (
        <svg viewBox="0 0 24 24">
          <path d="M12 1.5l8.5 3.2v6.6c0 5.4-3.6 9.6-8.5 11.2-4.9-1.6-8.5-5.8-8.5-11.2V4.7z" />
        </svg>
      );
    case 'patch':
      return (
        <svg viewBox="0 0 24 24">
          <path d="M5 4h2V2h2v2h6V2h2v2h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zm-0 6v10h14V10zm5.5 8.2l-3.2-3.2 1.4-1.4 1.8 1.8 4.8-4.8 1.4 1.4z" />
        </svg>
      );
  }
}
