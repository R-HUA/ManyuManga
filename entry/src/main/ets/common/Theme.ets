/**
 * 全局中性深浅色主题。
 */
export const PRIMARY: Resource = $r('app.color.primary');
export const PRIMARY_SOFT: Resource = $r('app.color.primary_soft');
export const ACCENT: Resource = $r('app.color.accent');
export const ACCENT_SOFT: Resource = $r('app.color.accent_soft');

export const BG: Resource = $r('app.color.bg');
export const CARD: Resource = $r('app.color.card');
export const SUB_CARD: Resource = $r('app.color.sub_card');
export const READER_BG: string = '#080A10';

export const TEXT_MAIN: Resource = $r('app.color.text_main');
export const TEXT_SUB: Resource = $r('app.color.text_sub');

export const CHIP_BG: Resource = $r('app.color.chip_bg');
export const DIVIDER: Resource = $r('app.color.divider');
export const TAB_INACTIVE: Resource = $r('app.color.tab_inactive');
export const BAR_LIGHT: Resource = $r('app.color.bar_surface');
export const BAR_TINT: Resource = $r('app.color.bar_tint');

export const STATUS_OK: Resource = $r('app.color.status_ok');
export const STATUS_WARN: Resource = $r('app.color.status_warn');
export const DANGER: Resource = $r('app.color.danger');
export const DANGER_SOFT: Resource = $r('app.color.danger_soft');

export const MEDAL_GOLD: Resource = $r('app.color.medal_gold');
export const MEDAL_SILVER: Resource = $r('app.color.medal_silver');
export const MEDAL_BRONZE: Resource = $r('app.color.medal_bronze');

export const COVER_R: number = 12;
export const CARD_R: number = 16;
export const CHIP_R: number = 14;

export const COVER_ASPECT_RATIO: number = 0.75;
export const TAB_BAR_HEIGHT: number = 64;

export const FONT_TITLE: number = 17;
export const FONT_BODY: number = 14;
export const FONT_CAPTION: number = 12;
export const FONT_TAB: number = 11;
export const FONT_BADGE: number = 10;

export const SPACE_XS: number = 4;
export const SPACE_S: number = 8;
export const SPACE_M: number = 12;
export const SPACE_L: number = 16;
export const SPACE_XL: number = 24;

export const MASK_DARK: string = 'rgba(8,10,16,0.68)';
export const PRIVACY_MASK: string = '#0E111A';

/** 同一内容宽度下，各图源保持相同的封面密度。 */
export function comicColumns(width: number): number {
  return Math.max(3, Math.floor((width + 12) / 116));
}
