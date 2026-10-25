import { SourceEntry, SourceAuth, sourceStore, sourceKey } from '../data/Sources';
import { MangaRouteParams } from '../common/Route';
import { suwayomi } from '../data/Suwayomi';
import { localSource } from '../data/LocalSource';
import { library } from '../data/Library';
import { Album, errorMessage } from '../models/Models';
import { BG, CARD, PRIMARY, TEXT_MAIN, TEXT_SUB } from '../common/Theme';
import { ROUTE_ALBUM, ROUTE_SEARCH } from '../common/Route';

@Component
export struct SourcesPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp('sourceVersion') @Watch('load') version: number = 0;
  @StorageProp('topRectHeight') topInset: number = 0;
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
  private instance: string = '';
  aboutToAppear(): void { this.load(); }
  private async load(): Promise<void> {
    try { this.sources = await sourceStore.list(); }
    catch (e) { this.error = errorMessage(e as Error); }
  }
  private async connect(): Promise<void> {
    this.busy = true; this.error = '';
    try {
      const modes: Array<SourceAuth> = ['none', 'basic', 'login'];
      const entries: Array<SourceEntry> = await suwayomi.connect(this.endpoint, this.name.trim() || 'Suwayomi', modes[this.authIndex], this.user, this.password,
        this.instance || `s${Date.now()}`);
      if (entries.length === 0) { throw new Error('服务端尚未安装书源，请先在服务端添加扩展'); }
      for (const entry of entries) { await sourceStore.save(entry); }
      this.password = ''; this.form = false; await this.load();
    } catch (e) { this.error = errorMessage(e as Error); }
    finally { this.busy = false; }
  }
  private async importLocal(): Promise<void> {
    this.busy = true; this.error = '';
    try {
      const album: Album | null = await localSource.importFiles('');
      if (album !== null) { await library.add(album); this.stack.pushPathByName(ROUTE_ALBUM, { aid: album.id } as MangaRouteParams); }
    } catch (e) { this.error = errorMessage(e as Error); }
    finally { this.busy = false; }
  }
  private settings(source: SourceEntry): void {
    if (source.kind === 'jm') { this.stack.pushPathByName('jmSettings', {} as MangaRouteParams); return; }
    if (source.kind === 'local') { this.importLocal(); return; }
    this.endpoint = source.endpoint; this.name = source.name.split(' · ')[0]; this.instance = source.instanceId;
    this.authIndex = source.auth === 'basic' ? 1 : source.auth === 'login' ? 2 : 0;
    this.user = ''; this.password = ''; this.form = true;
  }
  @Builder
  private ConnectionSheet() {
    Scroll() {
      Column({ space: 16 }) {
        Text(this.instance === '' ? '添加 Suwayomi' : '书源连接设置').fontSize(24).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN)
        TextInput({ text: this.name, placeholder: '服务名称' }).onChange((s: string) => { this.name = s; })
        TextInput({ text: this.endpoint, placeholder: '服务地址，如 http://192.168.1.10:4567' }).onChange((s: string) => { this.endpoint = s; })
        Select([{ value: '无需认证' }, { value: '基础认证' }, { value: '账号登录' }]).selected(this.authIndex).onSelect((index: number) => { this.authIndex = index; })
        if (this.authIndex > 0) {
          TextInput({ text: this.user, placeholder: '用户名' }).onChange((s: string) => { this.user = s; })
          TextInput({ text: this.password, placeholder: '密码' }).type(InputType.Password).onChange((s: string) => { this.password = s; })
        }
        if (this.error !== '') { Text(this.error).fontColor(TEXT_SUB) }
        Button(this.busy ? '正在连接…' : '连接并读取书源').width('100%').enabled(!this.busy).backgroundColor(PRIMARY).onClick(() => { this.connect(); })
      }.width('100%').padding(24)
    }.width('100%')
  }
  build() {
    Column({ space: 16 }) {
      Row() {
        Text('书源').fontSize(30).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN).layoutWeight(1)
        Button('添加').onClick(() => { this.instance = ''; this.endpoint = ''; this.name = ''; this.user = ''; this.password = ''; this.error = ''; this.form = true; })
      }.padding({ left: 20, right: 20, top: this.topInset + 12 }).width('100%')
      Button('搜索全部书源').width('90%').onClick(() => { this.stack.pushPathByName(ROUTE_SEARCH, {} as MangaRouteParams); })
      if (this.error !== '' && !this.form) { Text(this.error).fontColor(TEXT_SUB).padding(16) }
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.sources, (source: SourceEntry) => {
            Column({ space: 16 }) {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.book')).fontSize(28).fontColor([PRIMARY])
                Column({ space: 4 }) {
                  Text(source.name).fontColor(TEXT_MAIN).fontSize(17).fontWeight(FontWeight.Bold)
                  Text(source.kind === 'local' ? '压缩漫画与图片' : source.kind === 'jm' ? '独立在线书源' : source.language || source.endpoint).fontColor(TEXT_SUB).fontSize(12).maxLines(1)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: source.enabled }).onChange((enabled: boolean) => {
                  const updated: SourceEntry = JSON.parse(JSON.stringify(source)) as SourceEntry;
                  updated.enabled = enabled;
                  sourceStore.save(updated).catch((e: Error) => { this.error = errorMessage(e); this.load(); });
                })
              }.width('100%')
              if (source.kind === 'jm') {
                Row({ space: 10 }) {
                  TextInput({ text: this.jmNumber, placeholder: '输入漫画编号' }).layoutWeight(1).type(InputType.Number).onChange((s: string) => { this.jmNumber = s; })
                  Button('打开').enabled(source.enabled).onClick(() => {
                    if (!/^\d+$/.test(this.jmNumber.trim())) { this.error = '请输入正确的漫画编号'; return; }
                    this.stack.pushPathByName(ROUTE_ALBUM, { aid: sourceKey('jm', this.jmNumber.trim()) } as MangaRouteParams);
                  })
                }.width('100%')
              }
              Row({ space: 10 }) {
                Button(source.kind === 'local' ? '导入漫画' : '浏览').enabled(source.enabled && !this.busy).onClick(() => {
                  if (source.kind === 'local') { this.importLocal(); }
                  else if (source.kind === 'jm') { this.stack.pushPathByName('jmBrowse', {} as MangaRouteParams); }
                  else { this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: source.id } as MangaRouteParams); }
                })
                Button(source.kind === 'local' ? '查看漫画' : '设置').onClick(() => {
                  if (source.kind === 'local') { this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: source.id } as MangaRouteParams); }
                  else { this.settings(source); }
                })
                if (source.kind === 'suwayomi') {
                  Button('移除').onClick(() => { AlertDialog.show({ title: '移除书源', message: '书架、阅读记录和下载文件会保留。',
                    primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '移除', action: () => {
                      sourceStore.remove(source.id).catch((e: Error) => { this.error = errorMessage(e); });
                    } } }); })
                }
              }.width('100%')
            }.padding(20).width('100%').backgroundColor(CARD).borderRadius(24)
          }, (source: SourceEntry) => `${source.id}_${source.enabled}`)
        }.padding({ left: 20, right: 20, bottom: 110 }).width('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(BG)
    .bindSheet($$this.form, this.ConnectionSheet(), { height: '80%', dragBar: true })
  }
}
