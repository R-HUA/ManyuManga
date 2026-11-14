import uiMaterial from '@ohos.arkui.uiMaterial';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial, HdsNavigationTitleBarStyle, ScrollEffectType, SystemMaterialParams, TitleBarStyleOptions } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';

export const HDS_NATIVE_MATERIAL: SystemMaterialParams = {
  materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
};
export const HDS_TITLE_STYLE: TitleBarStyleOptions = {
  scrollEffectOpts: {
    enableScrollEffect: true,
    scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
    blurEffectiveStartOffset: LengthMetrics.vp(0),
    blurEffectiveEndOffset: LengthMetrics.vp(56)
  },
  systemMaterialEffect: HDS_NATIVE_MATERIAL
};

/** 显式关闭沉浸光感材质（如去除 Select 的默认高亮胶囊材质） */
export const EMPTY_MATERIAL: uiMaterial.Material = uiMaterial.Material.empty;

/** 沉浸材质只使用这四档。Toggle / Select / Slider 用 REGULAR。 */
export const IMMERSIVE_CONTROL_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN });
export const IMMERSIVE_TAB_BAR_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THIN });
export const IMMERSIVE_REGULAR_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });
export const IMMERSIVE_SHEET_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK });

/** 阅读器上下栏的深色着色（约 50% 不透明），只给材质加色，不遮挡材质。 */
export const READER_BAR_TINT: Resource = $r('app.color.reader_bar_tint');
/** 设备不支持沉浸光感时的降级底色（约 88% 不透明），配合系统模糊保证栏上文字可读。 */
export const READER_BAR_FALLBACK: Resource = $r('app.color.reader_bar_fallback');
/** 深色栏上的标题与图标色：深浅模式下都是白色。 */
const READER_BAR_ON: Resource = $r('app.color.on_overlay');
/** 深色栏上标题栏图标按钮的底色。 */
const READER_BAR_ICON_BG: Resource = $r('app.color.reader_bar_icon_bg');

/**
 * 当前设备能否渲染沉浸光感材质。按官方降级方案：先做 26.0.0 版本保护，再查询设备能力；查询异常按不支持处理。
 */
export function immersiveMaterialAvailable(): boolean {
  try {
    if (deviceInfo.apiAvailable('26.0.0')) {
      return uiMaterial.isImmersiveMaterialSupported();
    }
    return false;
  } catch (e) {
    return false;
  }
}

/**
 * 阅读器底栏气泡（bindPopup）的材质：REGULAR 加深色着色。
 * 气泡属于沉浸光感的生效范围；内容层不设背景色，否则会盖住材质。
 */
export const READER_BAR_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR, materialColor: READER_BAR_TINT });

function readerTitleBarStyle(background: Resource): HdsNavigationTitleBarStyle {
  return {
    backgroundStyle: { backgroundColor: background },
    contentStyle: {
      titleStyle: { mainTitleColor: READER_BAR_ON, mainTitleShadowColor: Color.Transparent },
      menuStyle: { backgroundColor: READER_BAR_ICON_BG, iconColor: READER_BAR_ON },
      backIconStyle: { backgroundColor: READER_BAR_ICON_BG, iconColor: READER_BAR_ON }
    }
  };
}

/**
 * 阅读器顶栏（HdsNavDestination 标题栏）：沿用全局 GRADIENT_BLUR 与 HDS 材质，
 * 背景板改为深色着色、标题与图标改为白色，使顶栏不随应用深浅模式变化，和底栏一致。
 * 26.0.0 起，配置 systemMaterialEffect 时 originalStyle 的 backgroundColor 支持自定义。
 */
export function readerTitleStyle(materialOn: boolean): TitleBarStyleOptions {
  const background: Resource = materialOn ? READER_BAR_TINT : READER_BAR_FALLBACK;
  return {
    scrollEffectOpts: HDS_TITLE_STYLE.scrollEffectOpts,
    originalStyle: readerTitleBarStyle(background),
    scrollEffectStyle: readerTitleBarStyle(background),
    systemMaterialEffect: HDS_NATIVE_MATERIAL
  };
}
