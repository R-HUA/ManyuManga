import uiMaterial from '@ohos.arkui.uiMaterial';
import { hdsMaterial, ScrollEffectType, SystemMaterialParams, TitleBarStyleOptions } from '@kit.UIDesignKit';
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

/**
 * 阅读器上下栏：固定深色半透明的沉浸光感。宿主用 WithTheme(DARK) 包住两栏，材质再叠一层深色着色，
 * 不跟随系统浅色主题；不支持沉浸材质的设备由 readerBarBackground() 的深色底兜底。
 */
export const READER_BAR_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR, materialColor: $r('app.color.reader_bar_tint') });

/** 支持沉浸材质时栏底透明，交给材质；不支持时用深色兜底底色，保证栏上文字可读。 */
export function readerBarBackground(): ResourceColor {
  try {
    return uiMaterial.isImmersiveMaterialSupported() ? Color.Transparent : $r('app.color.reader_bar_fallback');
  } catch (e) {
    return $r('app.color.reader_bar_fallback');
  }
}
