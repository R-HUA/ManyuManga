import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import promptAction from '@ohos.promptAction';
import { HDS_TITLE_STYLE, IMMERSIVE_REGULAR_MATERIAL, IMMERSIVE_SHEET_MATERIAL } from '../../common/ImmersiveMaterials';
import { SuwayomiConnectSheet } from './SuwayomiConnectSheet';
import { SourceSettingsSheet } from './SourceSettingsSheet';
import { SourceEntry, SourceAuth, SourceInstance, copySource, sourceStore } from '../../data/Sources';
import { localSource } from '../../data/LocalSource';
import { suwayomi } from '../../data/Suwayomi';
import { library } from '../../data/Library';
import { Album, asRecord, asString, errorMessage } from '../../models/Models';
import { SourcePresentation, presentationFor, registrablePresentation } from '../../data/source/SourceCatalog';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_BLOCK_RULES, ROUTE_JM_SETTINGS } from '../../common/Route';
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
  @State form: boolean = false;
  @State endpoint: string = '';
  @State name: string = '';
  @State user: string = '';
  @State password: string = '';
  @State authIndex: number = 0;
  @State error: string = '';
  @State busy: boolean = false;
  @State settingsForm: boolean = false;
  @State settingsToken: string = '';
  private scroller: Scroller = new Scroller();
  private instance: string = '';

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

  private async openConnect(): Promise<void> {
    try {
      const current: SourceInstance | null = await sourceStore.connection();
      this.instance = current === null ? '' : current.id;
      this.endpoint = current === null ? '' : current.endpoint;
      this.name = current === null ? '' : current.name;
      this.authIndex = current !== null && current.auth === 'basic' ? 1 : (current !== null && current.auth === 'login' ? 2 : 0);
      this.user = '';
      this.password = '';
      this.error = '';
      this.form = true;
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  private async connect(replace: boolean = false): Promise<void> {
    const current: SourceInstance | null = await sourceStore.connection();
    const base: string = this.endpoint.trim().replace(/\/+$/, '');
    if (!replace && current !== null && current.endpoint !== base) {
      this.getUIContext().showAlertDialog({
        title: '替换服务连接',
        message: '更换服务地址将停用原服务的扩展，并为新服务建立独立书源身份。已有书架与离线漫画会保留。',
        primaryButton: { value: '取消', action: (): void => {} },
        secondaryButton: { value: '替换并连接', action: (): void => { this.connect(true); } }
      });
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const modes: Array<SourceAuth> = ['none', 'basic', 'login'];
      const pres: SourcePresentation | null = registrablePresentation();
      await suwayomi.connect(
        this.endpoint,
        this.name.trim() || (pres === null ? 'Suwayomi' : pres.defaultName),
        modes[this.authIndex],
        this.user,
        this.password,
        this.instance,
        replace
      );
      this.password = '';
      this.form = false;
      await this.load();
      promptAction.showToast({ message: '已连接 Suwayomi 书库' });
    } catch (e) {
      this.error = errorMessage(e as Error);
    } finally {
      this.busy = false;
    }
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

  @Builder
  private ConnectionSheet() {
    SuwayomiConnectSheet({
      instance: this.instance,
      name: this.$name,
      endpoint: this.$endpoint,
      authIndex: this.$authIndex,
      user: this.$user,
      password: this.$password,
      error: this.$error,
      busy: this.$busy,
      connect: (): Promise<void> => this.connect()
    })
  }

  @Builder
  private SettingsSheet() {
    SourceSettingsSheet({
      token: this.settingsToken,
      close: (): void => {
        this.settingsForm = false;
      }
    })
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.error !== '' && !this.form) {
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
                  this.settingsToken = presentationFor('eh').settingsToken;
                  this.settingsForm = this.settingsToken !== '';
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
              ListItem() {
                this.NavRow('本源屏蔽规则', '管理仅对本地漫画生效的过滤词', (): void => {
                  this.stack.pushPathByName(ROUTE_BLOCK_RULES, { sourceId: this.entryFor('local')!.id } as MangaRouteParams);
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
      .bindSheet($$this.form, this.ConnectionSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: true,
        title: { title: 'Suwayomi' },
        systemMaterial: IMMERSIVE_SHEET_MATERIAL
      })
      .bindSheet($$this.settingsForm, this.SettingsSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        systemMaterial: IMMERSIVE_SHEET_MATERIAL
      })
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
