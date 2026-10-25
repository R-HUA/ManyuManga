/**
 * common/Theme.ets —— 全局主题 token
 * 规则：页面一律引用本文件常量，不得散落硬编码颜色；
 *       例外：一次性半透明遮罩 rgba 可内联（通用遮罩已统一收口在文末）。
 *
 * 深浅色双态：颜色 token 全部改为 $r 资源引用，浅色值在
 * resources/base/element/color.json、深色值在 resources/dark/element/color.json，
 * 跟随 ApplicationContext.setColorMode 自动切换——Settings 深色模式开关与系统
 * 深色模式均即时生效，无需页面监听。常量名与语义不变（Resource 类型，可直传
 * backgroundColor/fontColor 等接受 ResourceColor 的接口）。
 */
/* ===== 品牌色（契约 token） ===== */
/** 品牌粉：Tab 激活、收藏、强调 */
export const PRIMARY: Resource = $r('app.color.primary');
/** 主 CTA 蓝：开始阅读等主行动按钮 */
export const ACCENT: Resource = $r('app.color.accent');

/* ===== 背景与表面（契约 token） ===== */
/** 页面背景 */
export const BG: Resource = $r('app.color.bg');
/** 卡片表面 */
export const CARD: Resource = $r('app.color.card');
/** 阅读器画布背景（深邃黑，阅读器恒定深色不随主题切换） */
export const READER_BG: string = '#0D0D0D';

/* ===== 文本（契约 token） ===== */
/** 主文本 */
export const TEXT_MAIN: Resource = $r('app.color.text_main');
/** 次级文本 */
export const TEXT_SUB: Resource = $r('app.color.text_sub');

/* ===== 功能色（契约 token） ===== */
/** 胶囊/标签底色（半透明） */
export const CHIP_BG: Resource = $r('app.color.chip_bg');
/** 分割线 / 骨架屏底色 */
export const DIVIDER: Resource = $r('app.color.divider');
/** Tab 未选中 */
export const TAB_INACTIVE: Resource = $r('app.color.tab_inactive');
/** 顶栏/底栏毛玻璃衬底（原 BAR_LIGHT，bar_surface 资源） */
export const BAR_LIGHT: Resource = $r('app.color.bar_surface');

/* ===== 功能语义色（评审新增：镜像延迟灯 / 排行奖牌） ===== */
/** 镜像延迟指示灯：正常 */
export const STATUS_OK: Resource = $r('app.color.status_ok');
/** 镜像延迟指示灯：高延迟（> 500ms） */
export const STATUS_WARN: Resource = $r('app.color.status_warn');
/** 排行榜奖牌：金 / 银 / 铜 */
export const MEDAL_GOLD: Resource = $r('app.color.medal_gold');
export const MEDAL_SILVER: Resource = $r('app.color.medal_silver');
export const MEDAL_BRONZE: Resource = $r('app.color.medal_bronze');

/* ===== 圆角 vp（契约 token） ===== */
/** 封面圆角 */
export const COVER_R: number = 12;
/** 卡片圆角 */
export const CARD_R: number = 12;
/** 胶囊圆角 */
export const CHIP_R: number = 14;

/* ===== 结构与布局（派生 token） ===== */
/** 封面宽高比 3:4（传给 aspectRatio 的宽/高值） */
export const COVER_ASPECT_RATIO: number = 0.75;
/** 底部 Tab 栏高度 vp */
export const TAB_BAR_HEIGHT: number = 56;

/* ===== 通用字号 fp（派生 token，统一定义避免页面各自硬编码） ===== */
/** 区块标题 */
export const FONT_TITLE: number = 17;
/** 正文 */
export const FONT_BODY: number = 14;
/** 辅助说明/标签 */
export const FONT_CAPTION: number = 12;
/** Tab 文字（契约：11fp） */
export const FONT_TAB: number = 11;
/** 角标（契约卡片规范：10fp） */
export const FONT_BADGE: number = 10;

/* ===== 间距 vp（派生 token） ===== */
export const SPACE_XS: number = 4;
export const SPACE_S: number = 8;
export const SPACE_M: number = 12;
export const SPACE_L: number = 16;
export const SPACE_XL: number = 24;

/* ===== 通用半透明遮罩（高频一次性 rgba 收口，避免各页重复内联） ===== */
/** 深色全屏遮罩：错误弹层、阅读器 HUD 底 */
export const MASK_DARK: string = 'rgba(0,0,0,0.45)';
/** Index 防窥遮罩衬底（多任务卡片模糊前的不透明层） */
export const PRIVACY_MASK: string = '#0D0D0D';
