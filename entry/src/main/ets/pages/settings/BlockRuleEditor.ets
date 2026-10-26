import { IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
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

  build() {
    Column({ space: 12 }) {
      Text(this.sourceId === '' ? '对全部图源生效。关闭的规则不会过滤。' : '只过滤这一图源。关闭的规则不会过滤。')
        .fontSize(12)
        .fontColor(TEXT_SUB)
        .width('100%')
      Select([
        { value: '关键词' },
        { value: '精确标签' }
      ])
        .selected(this.kindIndex)
        .value(this.kindIndex === 1 ? '精确标签' : '关键词')
        .font({ size: 14, weight: FontWeight.Medium })
        .fontColor(TEXT_MAIN)
        .backgroundColor(SUB_CARD)
        .menuSystemMaterial(IMMERSIVE_REGULAR_MATERIAL)
        .onSelect((index: number) => {
          this.kindIndex = index;
        })
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
      Button('添加规则', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(PRIMARY)
        .width('100%')
        .height(40)
        .onClick(() => {
          this.addRule();
        })
      if (this.notice !== '') {
        Text(this.notice).fontSize(12).fontColor(DANGER).width('100%')
      }
      if (this.rules.length === 0) {
        Text('还没有规则').fontSize(12).fontColor(TEXT_SUB).width('100%')
      }
      ForEach(this.rules, (rule: BlockRule) => {
        Column({ space: 8 }) {
          Row() {
            Text(rule.kind === 'tag' ? '精确标签' : '关键词')
              .fontSize(12)
              .fontColor(PRIMARY)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: rule.enabled === 1 })
              .selectedColor(PRIMARY)
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
            .backgroundColor(SUB_CARD)
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
