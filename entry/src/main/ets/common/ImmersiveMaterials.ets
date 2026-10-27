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
    blurEffectiveEndOffset: LengthMetrics.vp(20)
  },
  systemMaterialEffect: HDS_NATIVE_MATERIAL
};

/** 沉浸材质只使用这四档。Toggle / Select / Slider 用 REGULAR。 */
export const IMMERSIVE_CONTROL_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN });
export const IMMERSIVE_TAB_BAR_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THIN, colorInvert: true });
export const IMMERSIVE_REGULAR_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });
export const IMMERSIVE_SHEET_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK });
