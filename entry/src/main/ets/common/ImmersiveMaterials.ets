import uiMaterial from '@ohos.arkui.uiMaterial';

/** 沉浸材质只使用这四档。Toggle / Select / Slider 用 REGULAR。 */
export const IMMERSIVE_CONTROL_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN });
export const IMMERSIVE_TAB_BAR_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THIN, colorInvert: true });
export const IMMERSIVE_REGULAR_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });
export const IMMERSIVE_SHEET_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK });
