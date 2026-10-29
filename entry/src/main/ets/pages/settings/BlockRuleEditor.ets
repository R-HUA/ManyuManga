import { SymbolGlyphModifier } from '@ohos.arkui.modifier';
import { IMMERSIVE_REGULAR_MATERIAL, IMMERSIVE_SHEET_MATERIAL, EMPTY_MATERIAL } from '../../common/ImmersiveMaterials';
import { EmptyView } from '../../common/Components';
import { CARD, DANGER, PRIMARY, SUB_CARD, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { BlockRule, blockTagsStore } from '../../data/stores/FilterStores';

@Component
export struct BlockRuleEditor {
  @Prop @Watch('reload') sourceId: string = '';
  @State rules: Array<BlockRule> = [];
  @State kindIndex: number = 0;
  @State valueText: string = '';
  @State namespaceText: string = '';
  @State notice: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    try {
      this.rules = await blockTagsStore.rulesFor(this.sourceId);
    } catch (_e) {
      this.notice = '没能读取屏蔽规则';
    }
  }

  private storedValue(): string {
    const value: string = this.valueText.trim();
    const namespace: string = this.namespaceText.trim();
    if (this.kindIndex === 1 && namespace !== '') {
      return `${namespace}:${value}`;
    }
    return value;
  }

  private async addRule(): Promise<void> {
    const value: string = this.storedValue();
    if (value === '') {
      this.notice = '规则内容不能为空';
      return;
    }
    await blockTagsStore.addRule(this.sourceId, this.kindIndex === 1 ? 'tag' : 'keyword', value);
    this.valueText = '';
    this.namespaceText = '';
    this.notice = '';
    await this.reload();
  }

  @Builder
  private KindMenu() {
    Menu() {
      MenuItem({
        content: '关键词',
        symbolEndIcon: this.kindIndex === 0 ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          this.kindIndex = 0;
        })
      MenuItem({
        content: '精确标签',
        symbolEndIcon: this.kindIndex === 1 ? new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          this.kindIndex = 1;
        })
    }
  }

  build() {
    Column({ space: 12 }) {
      Text(this.sourceId === '' ? '对全部图源生效。关闭的规则不会过滤。' : '只过滤这一图源。关闭的规则不会过滤。')
        .fontSize(12)
        .fontColor(TEXT_SUB)
        .width('100%')
        .padding({ left: 12, right: 12 })
      Column({ space: 12 }) {
      Row({ space: 12 }) {
        Text('规则类型')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        Row({ space: 4 }) {
          Text(this.kindIndex === 1 ? '精确标签' : '关键词')
            .fontSize(14)
            .fontColor(TEXT_SUB)
          SymbolGlyph($r('sys.symbol.arrowtriangle_down_fill'))
            .fontSize(10)
            .fontColor([TEXT_SUB])
        }
        .constraintSize({ minHeight: 40 })
        .padding({ left: 8, top: 4, bottom: 4 })
        .alignItems(VerticalAlign.Center)
        .bindMenu(this.KindMenu)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .constraintSize({ minHeight: 44 })
      if (this.kindIndex === 1) {
        TextInput({ text: this.namespaceText, placeholder: '命名空间，可留空' })
          .width('100%')
          .height(40)
          .backgroundColor(SUB_CARD)
          .fontColor(TEXT_MAIN)
          .placeholderColor(TEXT_SUB)
          .onChange((value: string) => {
            this.namespaceText = value;
          })
      }
      TextInput({ text: this.valueText, placeholder: this.kindIndex === 1 ? '标签名' : '关键词' })
        .width('100%')
        .height(40)
        .backgroundColor(SUB_CARD)
        .fontColor(TEXT_MAIN)
        .placeholderColor(TEXT_SUB)
        .onChange((value: string) => {
          this.valueText = value;
        })
        .onSubmit(() => {
          this.addRule();
        })
      Button('添加规则', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.EMPHASIZED })
        .fontSize(16).fontWeight(FontWeight.Medium)
        .width('100%')
        .height(40)
        .onClick(() => {
          this.addRule();
        })
      }.width('100%').padding(12).borderRadius(16).backgroundColor(CARD)
      if (this.notice !== '') {
        Text(this.notice).fontSize(12).fontColor(DANGER).width('100%')
      }
      if (this.rules.length === 0) {
        Text($r('app.string.rule_list_title')).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB).padding({ left: 12, top: 16 }).width('100%')
        EmptyView({ message: '还没有规则', showRetry: false, quiet: true })
      } else {
        Text($r('app.string.rule_list_title')).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SUB).padding({ left: 12, top: 16 }).width('100%')
      }
      ForEach(this.rules, (rule: BlockRule) => {
        Column({ space: 8 }) {
          Row() {
            Text(rule.kind === 'tag' ? '精确标签' : '关键词')
              .fontSize(12)
              .fontColor(PRIMARY)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: rule.enabled === 1 })
              .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
              .onChange((on: boolean) => {
                blockTagsStore.setEnabled(rule.id, on).then((): void => {
                  this.reload();
                }).catch((): void => {
                  this.notice = '没能更新这条规则';
                });
              })
          }
          .width('100%')
          Text(rule.value)
            .fontSize(14)
            .fontColor(TEXT_MAIN)
            .width('100%')
          Button('删除', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
            .fontSize(12)
            .fontColor(DANGER)
            .height(32)
            .onClick(() => {
              blockTagsStore.removeRule(rule.id).then((): void => {
                this.reload();
              }).catch((): void => {
                this.notice = '没能删除这条规则';
              });
            })
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor(CARD)
      }, (rule: BlockRule) => `${rule.id}_${rule.enabled}_${rule.value}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
