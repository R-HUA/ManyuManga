import { ToolBar, ToolBarOptions, ToolBarModifier, ItemState, SymbolGlyphModifier, LengthMetrics } from '@kit.ArkUI';
import { CARD } from './Theme';

/** 官方工具栏规范：默认高 52vp，平铺最多 4 个操作 + 1 个“更多”，不能与底部页签同时出现。 */
export const TOOLBAR_HEIGHT: number = 52;

export class ToolAction {
  label: string = '';
  symbol: Resource;
  enabled: boolean = true;
  danger: boolean = false;
  run: () => void = (): void => {};

  constructor(label: string, symbol: Resource, enabled: boolean, danger: boolean, run: () => void) {
    this.label = label;
    this.symbol = symbol;
    this.enabled = enabled;
    this.danger = danger;
    this.run = run;
  }
}

/** 把操作转换为 ToolBar 列表；不可逆操作的图标使用红色警告色。 */
export function buildToolBar(actions: Array<ToolAction>): ToolBarOptions {
  const list: ToolBarOptions = new ToolBarOptions();
  for (const action of actions.slice(0, 5)) {
    const icon: SymbolGlyphModifier = new SymbolGlyphModifier(action.symbol);
    if (action.danger) {
      icon.fontColor([$r('sys.color.warning')]);
    }
    list.push({
      content: action.label,
      action: action.run,
      state: action.enabled ? ItemState.ENABLE : ItemState.DISABLE,
      toolBarSymbolOptions: { normal: icon }
    });
  }
  return list;
}

/** 多选底部工具栏：52vp + 导航条避让。 */
@Component
export struct SelectionToolBar {
  @ObjectLink items: ToolBarOptions;
  @Prop bottomInset: number = 0;
  private controller: TabsController = new TabsController();
  private modifier: ToolBarModifier = new ToolBarModifier()
    .height(LengthMetrics.vp(TOOLBAR_HEIGHT))
    .backgroundColor(CARD);

  build() {
    Column() {
      ToolBar({ toolBarList: this.items, controller: this.controller, toolBarModifier: this.modifier })
    }
    .width('100%')
    .padding({ bottom: this.bottomInset })
    .backgroundColor(CARD)
  }
}
