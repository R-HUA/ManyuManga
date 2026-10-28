import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { BG, DIVIDER, TEXT_MAIN, TEXT_SUB, DANGER } from '../../common/Theme';
import { MangaRouteParams, ROUTE_SOURCE_BROWSE, ROUTE_SOURCE_SETTINGS } from '../../common/Route';
import { SourceEntry, SourceInstance, sourceStore } from '../../data/Sources';
import { errorMessage } from '../../models/Models';

@Component
export struct SuwayomiSourcesPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('sourceVersion') @Watch('load') version: number = 0;
  @State sources: Array<SourceEntry> = [];
  @State connected: boolean = false;
  @State private loading: boolean = true;
  @State private error: string = '';
  private generation: number = 0;
  private instanceName: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { this.generation++; }

  async load(): Promise<void> {
    const ticket: number = ++this.generation;
    this.loading = true;
    this.error = '';
    try {
      const connection: SourceInstance | null = await sourceStore.connection();
      const all: Array<SourceEntry> = await sourceStore.list();
      const hidden: Array<string> = await sourceStore.hiddenIds();
      if (ticket !== this.generation) { return; }
      this.connected = connection !== null;
      this.instanceName = connection === null ? '' : connection.name;
      this.sources = connection === null ? [] : all.filter((entry: SourceEntry): boolean =>
        entry.kind === 'suwayomi' && entry.instanceId === connection.id && entry.enabled && !hidden.includes(entry.id));
    } catch (e) {
      if (ticket === this.generation) { this.error = errorMessage(e as Error); }
    } finally {
      if (ticket === this.generation) { this.loading = false; }
    }
  }

  displayName(source: SourceEntry): string {
    const prefix: string = `${this.instanceName} · `;
    return source.name.startsWith(prefix) ? source.name.substring(prefix.length) : source.name;
  }

  build() {
    HdsNavDestination() {
      if (this.loading) {
        Column() {
          LoadingProgress().width(32).height(32)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.error !== '') {
        Column({ space: 12 }) {
          Text(this.error).fontColor(DANGER).fontSize(13)
          Button('重试', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
            .onClick(() => { this.load(); })
        }.width('100%').padding(24)
      } else if (!this.connected || this.sources.length === 0) {
        Column({ space: 14 }) {
          Text(this.connected ? '暂无可用扩展图源' : '尚未连接 Suwayomi 服务')
            .fontSize(14)
            .fontColor(TEXT_SUB)
          Button('前往图源设置', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
            .height(36)
            .fontSize(13)
            .onClick(() => {
              this.stack.pushPathByName(ROUTE_SOURCE_SETTINGS, {} as MangaRouteParams);
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding(24)
      } else {
        List({ scroller: this.scroller }) {
          ForEach(this.sources, (source: SourceEntry) => {
            ListItem() {
              Row({ space: 12 }) {
                Text(this.displayName(source))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(TEXT_MAIN)
                  .layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(16)
                  .fontColor([TEXT_SUB])
              }
              .width('100%')
              .constraintSize({ minHeight: 56 })
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .onClick(() => {
                this.stack.pushPathByName(ROUTE_SOURCE_BROWSE, { sourceId: source.id } as MangaRouteParams);
              })
            }
          }, (source: SourceEntry): string => source.id)
        }
        .width('100%')
        .height('100%')
        .divider({ strokeWidth: 0.5, color: DIVIDER, startMargin: 16, endMargin: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .titleBar({ content: { title: { mainTitle: 'Suwayomi' } }, style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .backgroundColor(BG)
  }
}
