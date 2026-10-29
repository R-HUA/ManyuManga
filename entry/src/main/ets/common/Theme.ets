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
/** 半模态卡片底：约 55% 不透明度，避免遮挡宿主材质滤镜。 */
export const SHEET_CARD: Resource = $r('app.color.sheet_card');
export const READER_BG: string = '#080A10';

export const TEXT_MAIN: Resource = $r('app.color.text_main');
export const TEXT_SUB: Resource = $r('app.color.text_sub');

export const CHIP_BG: Resource = $r('app.color.chip_bg');
export const DIVIDER: Resource = $r('app.color.divider');
export const TAB_INACTIVE: Resource = $r('app.color.tab_inactive');
export const BAR_LIGHT: Resource = $r('app.color.bar_surface');

export const STATUS_OK: Resource = $r('app.color.status_ok');
export const DANGER: Resource = $r('app.color.danger');
export const DANGER_SOFT: Resource = $r('app.color.danger_soft');

export const COVER_R: number = 12;
export const CHIP_R: number = 14;

export const COVER_ASPECT_RATIO: number = 0.75;
/** HDS 悬浮页签默认高度，用于内容与续读条避让。 */
export const TAB_BAR_HEIGHT: number = 56;
/** HDS MINI 模式标题栏标准高度规范（56vp）。 */
export const HDS_TITLE_BAR_HEIGHT: number = 56;

export const FONT_BODY: number = 14;
export const FONT_CAPTION: number = 12;

export const SPACE_S: number = 8;
export const SPACE_M: number = 12;
export const SPACE_L: number = 16;

export const MASK_DARK: string = 'rgba(8,10,16,0.68)';

/** 阅读器一级 HUD 与浮卡调色板：随深色画布或纸质画布联动切换，保持表面统一。 */
export class ReaderHudPalette {
  surface: string;
  capsule: string;
  border: string;
  text: string;
  textSub: string;
  faint: string;
  divider: string;

  constructor(surface: string, capsule: string, border: string, text: string, textSub: string, faint: string, divider: string) {
    this.surface = surface;
    this.capsule = capsule;
    this.border = border;
    this.text = text;
    this.textSub = textSub;
    this.faint = faint;
    this.divider = divider;
  }
}

export const HUD_DARK: ReaderHudPalette = new ReaderHudPalette(
  'rgba(28,28,32,0.88)',
  'rgba(28,28,32,0.84)',
  'rgba(255,255,255,0.10)',
  'rgba(255,255,255,0.92)',
  'rgba(255,255,255,0.64)',
  'rgba(255,255,255,0.36)',
  'rgba(255,255,255,0.10)'
);

export const HUD_PAPER: ReaderHudPalette = new ReaderHudPalette(
  'rgba(250,246,238,0.94)',
  'rgba(246,241,231,0.92)',
  'rgba(24,24,28,0.08)',
  'rgba(28,26,23,0.92)',
  'rgba(28,26,23,0.60)',
  'rgba(28,26,23,0.32)',
  'rgba(24,24,28,0.08)'
);

export function readerHudPalette(paper: boolean): ReaderHudPalette {
  return paper ? HUD_PAPER : HUD_DARK;
}

export const HUD_SURFACE: string = HUD_DARK.surface;
export const HUD_CAPSULE: string = HUD_DARK.capsule;
export const HUD_BORDER: string = HUD_DARK.border;
export const HUD_TEXT: string = HUD_DARK.text;
export const HUD_TEXT_SUB: string = HUD_DARK.textSub;
export const HUD_TEXT_FAINT: string = HUD_DARK.faint;
/** 九宫格热区校准蒙层的三种动作着色：上一页／呼出菜单／下一页。 */
export const ZONE_PREV: string = 'rgba(45,212,191,0.34)';
export const ZONE_MENU: string = 'rgba(251,191,36,0.30)';
export const ZONE_NEXT: string = 'rgba(96,165,250,0.34)';
export const ZONE_IDLE: string = 'rgba(148,163,184,0.20)';
/** 暖色温护眼滤镜基色；强度档位换算成透明度，45 档约等于旧版固定值。 */
const EYE_TINT_RGB: string = '255,185,85';
export function eyeComfortTint(level: number): string {
  return level <= 0 ? 'rgba(255,185,85,0)' : `rgba(${EYE_TINT_RGB},${(level / 100 * 0.4).toFixed(3)})`;
}

/** 同一内容宽度下，各图源保持相同的封面密度。 */
export function comicColumns(width: number): number {
  return Math.max(3, Math.floor((width + 12) / 116));
}

/** 中性进度色：浅色模式深灰、深色模式白色，用于进度条与滑杆，避免品牌色过度使用 */
export const NEUTRAL_PROGRESS: Resource = $r('sys.color.font_primary');
/** 三级文字色：已读章节等弱化信息 */
export const TEXT_TERTIARY: Resource = $r('sys.color.font_tertiary');
