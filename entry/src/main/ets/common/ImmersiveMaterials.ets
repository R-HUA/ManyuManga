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
 * 阅读器上下栏：沉浸光感材质挂在栏的外层容器上，栏内容再垫一层固定的深色半透明底（READER_BAR_BACKING）。
 * 材质负责光感与阴影；底色保证任何设备、任何材质档位下栏上文字都可读，不依赖材质是否真正渲染。
 * 注意：同一节点上不要再设 backgroundColor —— systemMaterial 会接管该节点的背景色。
 */
export const READER_BAR_MATERIAL: uiMaterial.ImmersiveMaterial =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });

/** 上下栏内容层的深色半透明底（约 80% 不透明），上下栏共用，确保两栏观感一致。 */
export const READER_BAR_BACKING: Resource = $r('app.color.reader_bar_backing');
