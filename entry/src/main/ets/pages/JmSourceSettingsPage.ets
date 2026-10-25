import promptAction from '@ohos.promptAction';
import { jmApi } from '../data/JmApi';
import { DomainSpeed } from '../models/Models';
import { blockTagsStore } from '../data/Stores';
import { IconCircleButton, EmptyView } from '../common/Components';
import {
  BG,
  CARD,
  SUB_CARD,
  PRIMARY,
  PRIMARY_SOFT,
  STATUS_OK,
  DANGER,
  DANGER_SOFT,
  TEXT_MAIN,
  TEXT_SUB,
  DIVIDER
} from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

@Component
export struct JmSourceSettingsPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 38;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 16;

  @State domains: Array<string> = [];
  @State currentDomain: string = '';
  @State domainSpeeds: Array<DomainSpeed> = [];
  @State testingSpeed: boolean = false;
  @State blockedTags: Array<string> = [];
  @State newTagInput: string = '';

  aboutToAppear(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    try {
      this.domains = jmApi.getDomains();
      this.currentDomain = this.domains[0] ?? '';
      this.blockedTags = await blockTagsStore.getList();
    } catch (_e) {
    }
  }

  private speedFor(d: string): DomainSpeed | undefined {
    return this.domainSpeeds.find((s: DomainSpeed) => s.domain === d);
  }

  private async runSpeedTest(): Promise<void> {
    if (this.testingSpeed) {
      return;
    }
    this.testingSpeed = true;
    try {
      this.domainSpeeds = await jmApi.testDomains();
      promptAction.showToast({ message: '节点测速已完成' });
    } catch (_e) {
      promptAction.showToast({ message: '测速失败，请检查网络连接' });
    } finally {
      this.testingSpeed = false;
    }
  }

  private async selectDomain(domain: string): Promise<void> {
    try {
      await jmApi.setPreferredDomain(domain);
      this.currentDomain = domain;
      promptAction.showToast({ message: `已切换至线路：${domain}` });
    } catch (_e) {
      promptAction.showToast({ message: '切换线路失败' });
    }
  }

  private async addTag(): Promise<void> {
    const t: string = this.newTagInput.trim();
    if (t === '') {
      return;
    }
    if (this.blockedTags.includes(t)) {
      promptAction.showToast({ message: '该屏蔽词已存在' });
      return;
    }
    await blockTagsStore.add(t);
    this.blockedTags = await blockTagsStore.getList();
    this.newTagInput = '';
    promptAction.showToast({ message: `已添加屏蔽词「${t}」` });
  }

  private async removeTag(tag: string): Promise<void> {
    await blockTagsStore.remove(tag);
    this.blockedTags = await blockTagsStore.getList();
    promptAction.showToast({ message: `已移除屏蔽词「${tag}」` });
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏
        Row({ space: 12 }) {
          IconCircleButton({
            symbol: $r('sys.symbol.chevron_left'),
            onTap: (): void => {
              this.stack.pop();
            }
          })

          Column({ space: 2 }) {
            Text('禁漫天堂 · 节点与过滤设置')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(TEXT_MAIN)
              .maxLines(1)
            Text('配置线路镜像节点与内容过滤')
              .fontSize(11)
              .fontColor(TEXT_SUB)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 10 })
        .backgroundColor(CARD)
        .border({ width: { bottom: 0.5 }, color: DIVIDER })

        Scroll() {
          Column({ space: 16 }) {
            // 1. 镜像节点测速与切换
            Column({ space: 14 }) {
              Row() {
                Column({ space: 2 }) {
                  Text('镜像节点与线路')
                    .fontSize(16)
                    .fontColor(TEXT_MAIN)
                    .fontWeight(FontWeight.Bold)
                  Text(`当前线路：${this.currentDomain || '默认线路'}`)
                    .fontSize(12)
                    .fontColor(TEXT_SUB)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button(this.testingSpeed ? '测速中…' : '并发测速', {
                  type: ButtonType.Capsule,
                  buttonStyle: ButtonStyleMode.NORMAL
                })
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PRIMARY)
                  .backgroundColor(PRIMARY_SOFT)
                  .height(32)
                  .enabled(!this.testingSpeed)
                  .onClick(() => {
                    this.runSpeedTest();
                  })
              }
              .width('100%')

              Column({ space: 8 }) {
                ForEach(this.domains, (domain: string) => {
                  Row({ space: 10 }) {
                    Circle({ width: 7, height: 7 })
                      .fill(domain === this.currentDomain ? STATUS_OK : TEXT_SUB)

                    Text(domain)
                      .fontSize(13)
                      .fontWeight(domain === this.currentDomain ? FontWeight.Bold : FontWeight.Medium)
                      .fontColor(domain === this.currentDomain ? PRIMARY : TEXT_MAIN)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    if (this.speedFor(domain) !== undefined) {
                      Text(this.speedFor(domain)!.ok ? `${this.speedFor(domain)!.ms} ms` : '不可达')
                        .fontSize(11)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.speedFor(domain)!.ok ? STATUS_OK : DANGER)
                        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                        .borderRadius(8)
                        .backgroundColor(CARD)
                    }

                    Button(domain === this.currentDomain ? '当前' : '切换', {
                      type: ButtonType.Capsule,
                      buttonStyle: ButtonStyleMode.NORMAL
                    })
                      .fontSize(12)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(domain === this.currentDomain ? TEXT_SUB : PRIMARY)
                      .backgroundColor(domain === this.currentDomain ? SUB_CARD : PRIMARY_SOFT)
                      .height(30)
                      .onClick(() => {
                        if (domain !== this.currentDomain) {
                          this.selectDomain(domain);
                        }
                      })
                  }
                  .padding({ left: 12, right: 10, top: 9, bottom: 9 })
                  .borderRadius(14)
                  .backgroundColor(SUB_CARD)
                  .width('100%')
                }, (domain: string) => `${domain}_${domain === this.currentDomain}_${this.speedFor(domain)?.ms ?? -1}`)
              }
              .width('100%')
            }
            .padding(18)
            .width('100%')
            .backgroundColor(CARD)
            .borderRadius(20)
            .border({ width: 0.5, color: DIVIDER })

            // 2. 内容屏蔽词过滤
            Column({ space: 14 }) {
              Column({ space: 4 }) {
                Text('内容屏蔽词')
                  .fontSize(16)
                  .fontColor(TEXT_MAIN)
                  .fontWeight(FontWeight.Bold)
                  .width('100%')
                Text('包含任意屏蔽词的作品将在发现、分类与搜索结果中自动过滤')
                  .fontSize(12)
                  .fontColor(TEXT_SUB)
                  .width('100%')
              }
              .width('100%')

              Row({ space: 8 }) {
                TextInput({ text: this.newTagInput, placeholder: '输入要屏蔽的题材或标签…' })
                  .layoutWeight(1)
                  .height(38)
                  .borderRadius(14)
                  .backgroundColor(SUB_CARD)
                  .fontColor(TEXT_MAIN)
                  .placeholderColor(TEXT_SUB)
                  .onChange((val: string) => {
                    this.newTagInput = val;
                  })
                  .onSubmit(() => {
                    this.addTag();
                  })

                Button('添加', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(PRIMARY)
                  .backgroundColor(PRIMARY_SOFT)
                  .height(38)
                  .onClick(() => {
                    this.addTag();
                  })
              }
              .width('100%')

              if (this.blockedTags.length === 0) {
                Text('暂无屏蔽词')
                  .fontSize(12)
                  .fontColor(TEXT_SUB)
                  .padding(12)
              } else {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.blockedTags, (tag: string) => {
                    Row({ space: 6 }) {
                      Text(tag)
                        .fontSize(12)
                        .fontColor(TEXT_MAIN)
                      SymbolGlyph($r('sys.symbol.xmark'))
                        .fontSize(12)
                        .fontColor([TEXT_SUB])
                    }
                    .padding({ left: 12, right: 10, top: 6, bottom: 6 })
                    .margin({ right: 8, bottom: 8 })
                    .borderRadius(14)
                    .backgroundColor(SUB_CARD)
                    .border({ width: 0.5, color: DIVIDER })
                    .onClick(() => {
                      this.removeTag(tag);
                    })
                  }, (tag: string) => tag)
                }
                .width('100%')
              }
            }
            .padding(18)
            .width('100%')
            .backgroundColor(CARD)
            .borderRadius(20)
            .border({ width: 0.5, color: DIVIDER })
          }
          .padding({ left: 16, right: 16, top: 16, bottom: 28 + this.bottomInset })
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG)
    }
    .hideTitleBar(true)
  }
}
