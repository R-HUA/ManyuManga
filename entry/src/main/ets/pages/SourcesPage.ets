import promptAction from '@ohos.promptAction';
import uiMaterial from '@ohos.arkui.uiMaterial';
import { SourceEntry, SourceAuth, sourceStore, sourceKey } from '../data/Sources';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_SEARCH } from '../common/Route';
import { suwayomi } from '../data/Suwayomi';
import { localSource } from '../data/LocalSource';
import { library } from '../data/Library';
import { Album, errorMessage } from '../models/Models';
import { IconCircleButton } from '../common/Components';
import {
  BG,
  CARD,
  SUB_CARD,
  PRIMARY,
  PRIMARY_SOFT,
  ACCENT,
  ACCENT_SOFT,
  DANGER,
  DANGER_SOFT,
  STATUS_OK,
  TEXT_MAIN,
  TEXT_SUB,
  DIVIDER,
  TAB_BAR_HEIGHT
} from '../common/Theme';
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
  @State jmNumber: string = '';
  @State globalQuery: string = '';
  private instance: string = '';

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.sources = await sourceStore.list();
      this.error = '';
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  private async connect(): Promise<void> {
    this.busy = true;
    this.error = '';
    try {
      const modes: Array<SourceAuth> = ['none', 'basic', 'login'];
      const entries: Array<SourceEntry> = await suwayomi.connect(
        this.endpoint,
        this.name.trim() || 'Suwayomi',
        modes[this.authIndex],
        this.user,
        this.password,
        this.instance || `s${Date.now()}`
      );
      if (entries.length === 0) {
        throw new Error('服务端尚未安装书源，请先在服务端添加扩展');
      }
      for (const entry of entries) {
        await sourceStore.save(entry);
      }
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

  private settings(source: SourceEntry): void {
    if (source.kind === 'jm') {
      this.stack.pushPathByName('jmSettings', {} as MangaRouteParams);
      return;
    }
    if (source.kind === 'local') {
      this.importLocal();
      return;
    }
    this.endpoint = source.endpoint;
    this.name = source.name.split(' · ')[0];
    this.instance = source.instanceId;
    this.authIndex = source.auth === 'basic' ? 1 : source.auth === 'login' ? 2 : 0;
    this.user = '';
    this.password = '';
    this.form = true;
  }

  @Builder
  private AuthModePill(label: string, index: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.authIndex === index ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.authIndex === index ? Color.White : TEXT_MAIN)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 9, bottom: 9 })
      .borderRadius(16)
      .backgroundColor(this.authIndex === index ? PRIMARY : SUB_CARD)
      .onClick(() => {
        this.authIndex = index;
      })
  }

  @Builder
  private ConnectionSheet() {
    Scroll() {
      Column({ space: 16 }) {
        Text(this.instance === '' ? '接入 Suwayomi 聚合服务' : '书源服务连接配置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .width('100%')

        Text('支持接入自建 Suwayomi-Server，自动枚举服务端已安装的漫画扩展并纳入全源并发检索与无缝换源。')
          .fontSize(12)
          .fontColor(TEXT_SUB)
          .lineHeight(18)
          .width('100%')

        Column({ space: 8 }) {
          Text('服务别名')
            .fontSize(12)
            .fontColor(TEXT_SUB)
          TextInput({ text: this.name, placeholder: '例如：家庭 NAS 书源库' })
            .height(44)
            .borderRadius(14)
            .backgroundColor(SUB_CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .onChange((s: string) => {
              this.name = s;
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column({ space: 8 }) {
          Text('服务端地址')
            .fontSize(12)
            .fontColor(TEXT_SUB)
          TextInput({ text: this.endpoint, placeholder: '如 http://192.168.1.10:4567' })
            .height(44)
            .borderRadius(14)
            .backgroundColor(SUB_CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .onChange((s: string) => {
              this.endpoint = s;
            })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column({ space: 8 }) {
          Text('鉴权方式')
            .fontSize(12)
            .fontColor(TEXT_SUB)
          Row({ space: 8 }) {
            this.AuthModePill('免密直连', 0)
            this.AuthModePill('基础认证', 1)
            this.AuthModePill('会话登录', 2)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        if (this.authIndex > 0) {
          TextInput({ text: this.user, placeholder: '认证用户名' })
            .height(44)
            .borderRadius(14)
            .backgroundColor(SUB_CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .onChange((s: string) => {
              this.user = s;
            })
          TextInput({ text: this.password, placeholder: '认证密码' })
            .height(44)
            .borderRadius(14)
            .backgroundColor(SUB_CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .type(InputType.Password)
            .onChange((s: string) => {
              this.password = s;
            })
        }

        if (this.error !== '') {
          Text(this.error)
            .fontSize(12)
            .fontColor(DANGER)
            .width('100%')
        }

        Text(this.busy ? '正在连接并同步扩展列表…' : '测试连接并导入书源')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(46)
          .borderRadius(23)
          .backgroundColor(PRIMARY)
          .opacity(this.busy ? 0.6 : 1.0)
          .onClick(() => {
            if (!this.busy) {
              this.connect();
            }
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 28 + this.bottomInset })
    }
    .width('100%')
  }

  @Builder
  private SourceActionPill(label: string, primary: boolean, danger: boolean, enabled: boolean, onTap: () => void) {
    Text(label)
      .fontSize(13)
      .fontWeight(primary ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(!enabled ? TEXT_SUB : (primary ? Color.White : (danger ? DANGER : TEXT_MAIN)))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 9, bottom: 9 })
      .borderRadius(16)
      .backgroundColor(primary ? PRIMARY : (danger ? DANGER_SOFT : SUB_CARD))
      .opacity(enabled ? 1.0 : 0.45)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
      .onClick(() => {
        if (enabled) {
          onTap();
        }
      })
  }

  build() {
    Column({ space: 12 }) {
      // Top Header
      Row({ space: 10 }) {
        Row({ space: 8 }) {
          Text('图源中枢')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_MAIN)
          Text(`${this.sources.filter((s: SourceEntry) => s.enabled).length} 启用`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(PRIMARY)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor(PRIMARY_SOFT)
        }
        .alignItems(VerticalAlign.Center)
        .layoutWeight(1)

        IconCircleButton({
          glyph: $r('sys.symbol.folder_badge_plus'),
          onTap: (): void => {
            this.importLocal();
          }
        })

        IconCircleButton({
          glyph: $r('sys.symbol.plus'),
          onTap: (): void => {
            this.instance = '';
            this.endpoint = '';
            this.name = '';
            this.user = '';
            this.password = '';
            this.error = '';
            this.form = true;
          }
        })
      }
      .padding({ left: 16, right: 16, top: this.topInset + 10, bottom: 4 })
      .width('100%')

      // Cross-source Search Bar
      Row({ space: 8 }) {
        Search({ value: this.globalQuery, placeholder: '并发检索全部已启用图源…' })
          .layoutWeight(1)
          .height(40)
          .backgroundColor(CARD)
          .onChange((val: string) => {
            this.globalQuery = val;
          })
          .onSubmit((val: string) => {
            this.stack.pushPathByName(ROUTE_SEARCH, { query: val.trim() } as MangaRouteParams);
          })
        Text('搜全源')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(18)
          .backgroundColor(PRIMARY)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          .onClick(() => {
            this.stack.pushPathByName(ROUTE_SEARCH, { query: this.globalQuery.trim() } as MangaRouteParams);
          })
      }
      .padding({ left: 16, right: 16 })
      .width('100%')

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

      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.sources, (source: SourceEntry) => {
            Column({ space: 14 }) {
              Row({ space: 12 }) {
                Stack({ alignContent: Alignment.Center }) {
                  SymbolGlyph(source.kind === 'jm'
                    ? $r('sys.symbol.compass')
                    : (source.kind === 'local' ? $r('sys.symbol.folder') : $r('sys.symbol.externaldrive')))
                    .fontSize(22)
                    .fontColor([source.kind === 'jm' ? ACCENT : PRIMARY])
                }
                .width(44)
                .height(44)
                .borderRadius(14)
                .backgroundColor(source.kind === 'jm' ? ACCENT_SOFT : PRIMARY_SOFT)

                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Text(source.name)
                      .fontColor(TEXT_MAIN)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Circle({ width: 6, height: 6 })
                      .fill(source.enabled ? STATUS_OK : TEXT_SUB)
                  }
                  Text(source.kind === 'local'
                    ? '本地 CBZ / ZIP 归档与目录'
                    : (source.kind === 'jm' ? '内置加密图源 · 精选广场 / 多维片库 / 镜像测速' : `${source.language ? source.language + ' · ' : ''}${source.endpoint}`))
                    .fontColor(TEXT_SUB)
                    .fontSize(12)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Toggle({ type: ToggleType.Switch, isOn: source.enabled })
                  .selectedColor(PRIMARY)
                  .systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
                  .onChange((enabled: boolean) => {
                    const updated: SourceEntry = JSON.parse(JSON.stringify(source)) as SourceEntry;
                    updated.enabled = enabled;
                    sourceStore.save(updated).catch((e: Error) => {
                      this.error = errorMessage(e);
                      this.load();
                    });
                  })
              }
              .width('100%')

              if (source.kind === 'jm') {
                Row({ space: 8 }) {
                  TextInput({ text: this.jmNumber, placeholder: '输入 JM 纯数字车号直达详情…' })
                    .layoutWeight(1)
                    .height(38)
                    .borderRadius(14)
                    .backgroundColor(SUB_CARD)
                    .fontColor(TEXT_MAIN)
                    .placeholderColor(TEXT_SUB)
                    .type(InputType.Number)
                    .onChange((s: string) => {
                      this.jmNumber = s;
                    })
                  Text('车号直达')
                    .fontSize(12)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(source.enabled ? PRIMARY : TEXT_SUB)
                    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                    .borderRadius(14)
                    .backgroundColor(PRIMARY_SOFT)
                    .onClick(() => {
                      if (!source.enabled) {
                        return;
                      }
                      const clean: string = this.jmNumber.trim().replace(/^[jJ][mM]/, '');
                      if (!/^\d+$/.test(clean)) {
                        this.error = '请输入有效的纯数字漫画编号';
                        return;
                      }
                      this.stack.pushPathByName(ROUTE_ALBUM, { aid: sourceKey('jm', clean) } as MangaRouteParams);
                    })
                }
                .width('100%')
              }

              Row({ space: 10 }) {
                this.SourceActionPill(
                  source.kind === 'local' ? '导入漫画包' : (source.kind === 'jm' ? '进入发现广场' : '检索此源'),
                  true,
                  false,
                  source.enabled && !this.busy,
                  () => {
                    if (source.kind === 'local') {
                      this.importLocal();
                    } else if (source.kind === 'jm') {
                      this.stack.pushPathByName('jmBrowse', {} as MangaRouteParams);
                    } else {
                      this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: source.id } as MangaRouteParams);
                    }
                  }
                )
                this.SourceActionPill(
                  source.kind === 'local' ? '已导入列表' : (source.kind === 'jm' ? '节点与屏蔽词' : '连接配置'),
                  false,
                  false,
                  true,
                  () => {
                    if (source.kind === 'local') {
                      this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: source.id } as MangaRouteParams);
                    } else {
                      this.settings(source);
                    }
                  }
                )
                if (source.kind === 'suwayomi') {
                  this.SourceActionPill(
                    '移除',
                    false,
                    true,
                    true,
                    () => {
                      this.getUIContext().showAlertDialog({
                        title: '移除书源',
                        message: `确定移除「${source.name}」吗？书架中的漫画、阅读记录与离线文件均会保留。`,
                        primaryButton: { value: '取消', action: () => {} },
                        secondaryButton: {
                          value: '移除',
                          fontColor: DANGER,
                          action: () => {
                            sourceStore.remove(source.id).catch((e: Error) => {
                              this.error = errorMessage(e);
                            });
                          }
                        }
                      });
                    }
                  )
                }
              }
              .width('100%')
            }
            .padding(16)
            .width('100%')
            .backgroundColor(CARD)
            .borderRadius(20)
            .border({ width: 0.5, color: DIVIDER })
          }, (source: SourceEntry) => `${source.id}_${source.enabled}`)
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
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
    .bindSheet($$this.form, this.ConnectionSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: CARD,
      systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK })
    })
  }
}
