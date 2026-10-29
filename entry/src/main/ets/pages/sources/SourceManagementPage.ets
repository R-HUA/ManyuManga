import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import promptAction from '@ohos.promptAction';
import { HDS_TITLE_STYLE, IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { SourceEntry, SourceInstance, copySource, sourceStore } from '../../data/Sources';
import { localSource } from '../../data/LocalSource';
import { library } from '../../data/Library';
import { Album, asRecord, asString, errorMessage } from '../../models/Models';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_EH_SITE, ROUTE_JM_SETTINGS, ROUTE_SUWAYOMI_CONNECT } from '../../common/Route';
import { BG, CARD, DIVIDER, DANGER, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

/**
 * 图源设置页：将各图源的显示开关与专属设置清晰拆行，消除旧版复用图源页导致的点击错乱与冗余排序抽屉。
 */
@Component
export struct SourceManagementPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('sourceVersion') @Watch('load') version: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  @State sources: Array<SourceEntry> = [];
  @State hidden: Array<string> = [];
  @State connectionLabel: string = '未连接';
  @State error: string = '';
  @State busy: boolean = false;
  private scroller: Scroller = new Scroller();

  toggleHidden: (id: string, hidden: boolean) => Promise<void> =
    (id: string, hidden: boolean): Promise<void> => sourceStore.setHidden(id, hidden);
  enableSource: (source: SourceEntry) => Promise<void> =
    (source: SourceEntry): Promise<void> => sourceStore.save(source);
  reportError: (message: string) => void = (message: string): void => {
    this.error = message;
  };
  changed: () => void = (): void => {
    this.load();
  };

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    try {
      const all: Array<SourceEntry> = await sourceStore.list();
      const hiddenIds: Array<string> = await sourceStore.hiddenIds();
      const connection: SourceInstance | null = await sourceStore.connection();
      this.sources = all.filter((entry: SourceEntry): boolean => entry.kind !== 'suwayomi');
      this.hidden = hiddenIds;
      this.connectionLabel = connection === null ? '未连接' : `${connection.name} (${connection.endpoint})`;
      this.error = '';
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  private entryFor(kind: string): SourceEntry | undefined {
    return this.sources.find((entry: SourceEntry): boolean => entry.kind === kind);
  }

  isHidden(id: string): boolean {
    return this.hidden.includes(id);
  }

  async applyHidden(id: string, hidden: boolean): Promise<void> {
    if (this.busy || this.isHidden(id) === hidden) {
      return;
    }
    this.busy = true;
    const previous: Array<string> = this.hidden.slice();
    const next: Array<string> = this.hidden.filter((value: string): boolean => value !== id);
    if (hidden) {
      next.push(id);
    }
    this.hidden = next;
    try {
      await this.toggleHidden(id, hidden);
      const source: SourceEntry | undefined = this.sources.find((entry: SourceEntry): boolean => entry.id === id);
      if (!hidden && source !== undefined && !source.enabled) {
        const updated: SourceEntry = copySource(source);
        updated.enabled = true;
        await this.enableSource(updated);
      }
      this.changed();
    } catch (e) {
      this.hidden = previous;
      this.reportError(errorMessage(e as Error));
      this.getUIContext().getPromptAction().showToast({ message: errorMessage(e as Error) });
    } finally {
      this.busy = false;
    }
  }

  async enable(id: string): Promise<void> {
    const source: SourceEntry | undefined = this.sources.find((entry: SourceEntry): boolean => entry.id === id);
    if (this.busy || source === undefined || source.enabled) {
      return;
    }
    this.busy = true;
    try {
      const updated: SourceEntry = copySource(source);
      updated.enabled = true;
      await this.enableSource(updated);
      this.changed();
    } catch (e) {
      this.reportError(errorMessage(e as Error));
      this.getUIContext().getPromptAction().showToast({ message: errorMessage(e as Error) });
    } finally {
      this.busy = false;
    }
  }

  private openConnect(): void {
    this.stack.pushPathByName(ROUTE_SUWAYOMI_CONNECT, { sourceId: 'suwayomi' } as MangaRouteParams);
  }

  private async importLocal(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const album: Album | null = await localSource.importFiles('');
      if (album !== null) {
        await library.add(album);
        promptAction.showToast({ message: `已导入《${album.name}》` });
        this.stack.pushPathByName(ROUTE_ALBUM, { aid: album.id, fromLibrary: true } as MangaRouteParams);
      }
    } catch (e) {
      this.error = errorMessage(e as Error);
    } finally {
      this.busy = false;
    }
  }

  @Builder
  private GroupTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(TEXT_SUB)
      .width('100%')
      .padding({ left: 12, top: 16, bottom: 8 })
  }

  @Builder
  private NavRow(title: string, subtitle: string, onTap: () => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
        if (subtitle !== '') {
          Text(subtitle)
            .fontSize(12)
            .fontColor(TEXT_SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([TEXT_SUB])
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  private VisibilityRow(source: SourceEntry, subtitle: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text('在图源页显示')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_MAIN)
        Text(subtitle)
          .fontSize(12)
          .fontColor(TEXT_SUB)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: !this.isHidden(source.id) && source.enabled })
        .enabled(!this.busy)
        .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
        .onChange((on: boolean) => {
          this.applyHidden(source.id, !on);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }

  build() {
    HdsNavDestination() {
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
          ListItem() { this.GroupTitle('Suwayomi') }
          ListItemGroup() {
            ListItem() {
              this.NavRow('服务端连接配置', this.connectionLabel, (): void => {
                this.openConnect();
              })
            }
          }
          .backgroundColor(CARD)
          .borderRadius(16)
          .padding({ top: 4, bottom: 4 })

          if (this.entryFor('jm') !== undefined) {
            ListItem() { this.GroupTitle('禁漫天堂') }
            ListItemGroup() {
              ListItem() {
                this.VisibilityRow(this.entryFor('jm')!, '控制是否在图源列表中展示禁漫入口')
              }
              ListItem() {
                this.NavRow('节点与分流设置', 'API 域名、图片分流与连通性测速', (): void => {
                  this.stack.pushPathByName(ROUTE_JM_SETTINGS, {} as MangaRouteParams);
                })
              }
            }
            .backgroundColor(CARD)
            .borderRadius(16).padding({ top: 4, bottom: 4 })
            .divider({ strokeWidth: '1px', color: DIVIDER, startMargin: 12, endMargin: 12 })
          }

          if (this.entryFor('eh') !== undefined) {
            ListItem() { this.GroupTitle('E-Hentai / ExHentai') }
            ListItemGroup() {
              ListItem() {
                this.VisibilityRow(this.entryFor('eh')!, '控制是否在图源列表中展示画廊入口')
              }
              ListItem() {
                this.NavRow('站点与账号设置', '表里站切换、Cookie 登录与标签汉化', (): void => {
                  this.stack.pushPathByName(ROUTE_EH_SITE, { sourceId: 'eh' } as MangaRouteParams);
                })
              }
            }
            .backgroundColor(CARD)
            .borderRadius(16).padding({ top: 4, bottom: 4 })
            .divider({ strokeWidth: '1px', color: DIVIDER, startMargin: 12, endMargin: 12 })
          }

          if (this.entryFor('local') !== undefined) {
            ListItem() { this.GroupTitle('本地漫画') }
            ListItemGroup() {
              ListItem() {
                this.VisibilityRow(this.entryFor('local')!, '控制是否在图源列表中展示本地漫画')
              }
              ListItem() {
                this.NavRow('导入本地漫画包', '选择本地 ZIP / CBZ 归档或图片文件夹导入书架', (): void => {
                  this.importLocal();
                })
              }
            }
            .backgroundColor(CARD)
            .borderRadius(16).padding({ top: 4, bottom: 4 })
            .divider({ strokeWidth: '1px', color: DIVIDER, startMargin: 12, endMargin: 12 })
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .contentEndOffset(28 + this.bottomInset)
        .scrollBar(BarState.Off)
        .clip(false)
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({ content: { title: { mainTitle: '图源设置' } }, style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .backgroundColor(BG)
    .onReady((context: NavDestinationContext) => {
      const params: Record<string, Object> | null = asRecord(context.pathInfo.param as Object);
      if (params !== null && asString(params['sourceId']) === 'suwayomi') { this.openConnect(); }
    })
  }
}
