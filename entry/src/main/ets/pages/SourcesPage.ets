import { HdsNavigation, HdsNavigationTitleMode, TitleSize } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import { SourceEntry, SourceInstance, sourceStore } from '../data/Sources';
import { errorMessage } from '../models/Models';
import { SourceEntryCard } from './sources/SourceEntryCard';
import { SOURCE_SECTIONS, presentationFor } from '../data/source/SourceCatalog';
import { MangaRouteParams, ROUTE_SEARCH, ROUTE_SUWAYOMI_LIBRARY } from '../common/Route';
import { BG, CARD, DIVIDER, DANGER, TEXT_MAIN, TEXT_SUB, TAB_BAR_HEIGHT } from '../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

@Component
export struct SourcesPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('sourceVersion') @Watch('load') version: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';

  @State sources: Array<SourceEntry> = [];
  @State error: string = '';
  @State private connectionLabel: string = '未连接';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const all: Array<SourceEntry> = await sourceStore.list();
      const hidden: Array<string> = await sourceStore.hiddenIds();
      const connection: SourceInstance | null = await sourceStore.connection();
      const visible: Array<SourceEntry> = all.filter((entry: SourceEntry): boolean =>
        entry.kind !== 'suwayomi' && !hidden.includes(entry.id));
      const ordered: Array<SourceEntry> = [];
      for (const section of SOURCE_SECTIONS) {
        for (const item of visible) {
          if (presentationFor(item.kind).section === section) {
            ordered.push(item);
          }
        }
      }
      this.sources = ordered;
      this.connectionLabel = connection === null ? '未连接服务端' : `已连接 ${connection.name}`;
      this.error = '';
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  build() {
    HdsNavigation() {
      Column() {
        if (this.error !== '') {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(16)
              .fontColor([DANGER])
            Text(this.error)
              .fontColor(TEXT_SUB)
              .fontSize(12)
              .layoutWeight(1)
          }
          .padding(12)
          .margin({ left: 16, right: 16, bottom: 8 })
          .borderRadius(14)
          .backgroundColor(CARD)
        }

        List({ scroller: this.scroller }) {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('Suwayomi')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(TEXT_MAIN)
                if (this.connectionLabel === '未连接服务端') {
                Text(this.connectionLabel)
                  .fontSize(12)
                  .fontColor(TEXT_SUB)
                  .maxLines(1)
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(16)
                .fontColor([TEXT_SUB])
            }
            .width('100%')
            .constraintSize({ minHeight: 60 })
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.99 })
            .onClick(() => {
              this.stack.pushPathByName(ROUTE_SUWAYOMI_LIBRARY, {} as MangaRouteParams);
            })
          }

          ForEach(this.sources, (source: SourceEntry) => {
            ListItem() {
              SourceEntryCard({
                source: source,
                busy: false,
                settingsOnly: false,
                showSettings: false,
                reportError: (message: string): void => {
                  this.error = message;
                },
                reloadSources: (): void => {
                  this.load();
                }
              })
            }
          }, (source: SourceEntry) => source.id)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0.5, color: DIVIDER, startMargin: 16, endMargin: 16 })
        .contentEndOffset((this.breakpoint === 'lg' ? 16 : TAB_BAR_HEIGHT + 16) + this.bottomInset)
        .scrollBar(BarState.Off)
        .clip(false)
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      content: {
        title: { mainTitle: '图源', mainTitleSize: TitleSize.TITLE_ML },
        menu: {
          value: [
            {
              content: {
                icon: $r('sys.symbol.magnifyingglass'),
                label: '搜索全部图源',
                action: (): void => {
                  this.stack.pushPathByName(ROUTE_SEARCH, { scope: 'all' } as MangaRouteParams);
                }
              }
            }
          ]
        }
      },
      style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack)
    .hideBackButton(true)
    .bindToScrollable([this.scroller])
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
