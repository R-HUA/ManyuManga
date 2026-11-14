import { HdsNavDestination, HdsNavDestinationTitleMode, TextStyleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import promptAction from '@ohos.promptAction';
import { jmApi } from '../data/JmApi';
import { DomainSpeed } from '../models/Models';
import { MangaRouteParams, ROUTE_BLOCK_RULES } from '../common/Route';
import { BG, CARD, PRIMARY, STATUS_OK, DANGER, TEXT_MAIN, TEXT_SUB, DIVIDER } from '../common/Theme';
import { SettingsActionRow, settingsRowRadius } from './settings/SettingsRows';
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
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    try {
      this.domains = jmApi.getDomains();
      this.currentDomain = this.domains[0] ?? '';
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

  @Builder
  private DomainRow(domain: string) {
    Row({ space: 12 }) {
      Text(domain)
        .fontSize(16)
        .fontColor(TEXT_MAIN)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.testingSpeed) {
        // 测速进行中：行尾时延位置显示小号加载指示，结果返回后替换为时延。
        LoadingProgress()
          .width(20)
          .height(20)
          .color(TEXT_SUB)
          .accessibilityText('测速中')
      } else if (this.speedFor(domain) !== undefined) {
        Text(this.speedFor(domain)!.ok ? `${this.speedFor(domain)!.ms} ms` : '不可达')
          .fontSize(12)
          .fontColor(this.speedFor(domain)!.ok ? STATUS_OK : DANGER)
      }
      Row() {
        if (domain === this.currentDomain) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(20)
            .fontColor([PRIMARY])
            .accessibilityText('当前线路')
        }
      }
      .width(24)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    HdsNavDestination() {
      List({ scroller: this.scroller }) {
        // 线路：整行点按切换，当前线路行尾打勾；测速结果显示在行尾。
        ListItemGroup({ header: this.GroupHeader('镜像线路') }) {
          ForEach(this.domains, (domain: string, index: number) => {
            ListItem() {
              this.DomainRow(domain)
            }
            .backgroundColor(CARD)
            .borderRadius(settingsRowRadius(index, this.domains.length))
            .onClick(() => {
              if (domain !== this.currentDomain) {
                this.selectDomain(domain);
              }
            })
          }, (domain: string) => `${domain}_${domain === this.currentDomain}_${this.testingSpeed}_${this.speedFor(domain)?.ms ?? -1}_${this.speedFor(domain)?.ok ?? false}`)
        }
        .divider({ strokeWidth: '1px', color: DIVIDER, startMargin: 12, endMargin: 12 })

        ListItemGroup({ header: this.GroupHeader('过滤') }) {
          ListItem() {
            SettingsActionRow({
              title: '本源屏蔽规则',
              onTap: (): void => {
                this.stack.pushPathByName(ROUTE_BLOCK_RULES, { sourceId: 'jm' } as MangaRouteParams);
              }
            })
          }
          .backgroundColor(CARD)
          .borderRadius(settingsRowRadius(0, 1))
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .contentEndOffset(28 + this.bottomInset)
      .scrollBar(BarState.Off)
      .clip(false)
    }
    .titleBar({
      content: {
        title: { mainTitle: '节点与过滤设置' },
        menu: {
          value: [{
            content: {
              // 文字按钮直接说明动作；测速期间置灰，进度显示在各线路行尾。
              label: '测速',
              type: TextStyleMode.NORMAL,
              isEnabled: !this.testingSpeed,
              action: (): void => { this.runSpeedTest(); }
            }
          }]
        }
      },
      style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .backgroundColor(BG)
  }

  @Builder
  private GroupHeader(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(TEXT_SUB)
      .width('100%')
      .padding({ left: 12, top: 16, bottom: 8 })
  }
}
