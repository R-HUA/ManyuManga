import { HdsNavigation } from '@kit.UIDesignKit';
import { SuwayomiConnectSheet } from './sources/SuwayomiConnectSheet';
import { SourceSettingsSheet } from './sources/SourceSettingsSheet';
import promptAction from '@ohos.promptAction';
import { IMMERSIVE_SHEET_MATERIAL, HDS_TITLE_STYLE } from '../common/ImmersiveMaterials';
import { SourceEntry, SourceAuth, SourceInstance, sourceStore } from '../data/Sources';
import { localSource } from '../data/LocalSource';
import { suwayomi } from '../data/Suwayomi';
import { library } from '../data/Library';
import { Album, errorMessage } from '../models/Models';
import { presentationFor, registrablePresentation, SourcePresentation } from '../data/source/SourceCatalog';
import { SourceEntryCard } from './sources/SourceEntryCard';
import { IconCircleButton } from '../common/Components';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_SEARCH } from '../common/Route';
import { SearchSuggestField } from './search/SearchSuggestField';
import { BG, CARD, DANGER, TEXT_MAIN, TEXT_SUB, TAB_BAR_HEIGHT } from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

@Component
export struct SourcesPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('sourceVersion') @Watch('load') version: number = 0;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';

  @State sources: Array<SourceEntry> = [];
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
  @State private connectionLabel: string = '未连接';
  private scroller: Scroller = new Scroller();
  private instance: string = '';

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.sources = await sourceStore.list();
      const connection: SourceInstance | null = await sourceStore.connection();
      this.connectionLabel = connection === null ? '未连接' : connection.name;
      this.error = '';
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
      const entries: Array<SourceEntry> = await suwayomi.connect(
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
      promptAction.showToast({ message: `已同步 ${entries.length} 个服务端扩展书源` });
    } catch (e) {
      this.error = errorMessage(e as Error);
    } finally {
      this.busy = false;
    }
  }

  private async importLocal(): Promise<void> {
    this.busy = true;
    this.error = '';
    try {
      const album: Album | null = await localSource.importFiles('');
      if (album !== null) {
        await library.add(album);
        this.stack.pushPathByName(ROUTE_ALBUM, { aid: album.id } as MangaRouteParams);
      }
    } catch (e) {
      this.error = errorMessage(e as Error);
    } finally {
      this.busy = false;
    }
  }

  private async openConnect(_source: SourceEntry, _fresh: boolean): Promise<void> {
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
    } catch (e) { this.error = errorMessage(e as Error); }
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
    HdsNavigation() {
      Column({ space: 12 }) {
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
        .margin({ left: 16, right: 16 })
        .borderRadius(14)
        .backgroundColor(CARD)
      }

      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Row({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.externaldrive')).fontSize(22).fontColor([TEXT_MAIN]).width(46).height(46)
            Column({ space: 4 }) {
              Text('Suwayomi').fontSize(16).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN)
              Text(this.connectionLabel).fontSize(12).fontColor(TEXT_SUB).maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            IconCircleButton({ glyph: $r('sys.symbol.gearshape'), onTap: (): void => { this.openConnect(new SourceEntry(), false); } })
          }.width('100%').padding(16).backgroundColor(CARD).borderRadius(18)
          .onClick(() => { this.openConnect(new SourceEntry(), false); })
          ForEach(this.sources, (source: SourceEntry) => {
            SourceEntryCard({
              source: source,
              busy: this.busy,
              reportError: (message: string): void => {
                this.error = message;
              },
              connectSource: (entry: SourceEntry): void => {
                this.openConnect(entry, false);
              },
              openSettings: (entry: SourceEntry): void => {
                this.settingsToken = presentationFor(entry.kind).settingsToken;
                this.settingsForm = this.settingsToken !== '';
              },
              importLocal: (): void => {
                this.importLocal();
              },
              reloadSources: (): void => {
                this.load();
              }
            })
          }, (source: SourceEntry) => source.id)
        }
        .padding({
          left: 16,
          right: 16,
          bottom: (this.breakpoint === 'lg' ? 28 : TAB_BAR_HEIGHT + 28) + this.bottomInset
        })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off).align(Alignment.TopStart).clip(false)
      }.width('100%').height('100%')
    }
    .titleBar({ content: { title: { mainTitle: '图源' }, menu: { value: [
      { content: { icon: $r('sys.symbol.magnifyingglass'), label: '搜索全部图源', action: (): void => { this.stack.pushPathByName(ROUTE_SEARCH, { scope: 'all' } as MangaRouteParams); } } }
    ] } }, style: HDS_TITLE_STYLE, avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .mode(NavigationMode.Stack).hideBackButton(true).bindToScrollable([this.scroller])
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
    .bindSheet($$this.form, this.ConnectionSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      systemMaterial: IMMERSIVE_SHEET_MATERIAL
    })
    .bindSheet($$this.settingsForm, this.SettingsSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      systemMaterial: IMMERSIVE_SHEET_MATERIAL
    })
  }
}
