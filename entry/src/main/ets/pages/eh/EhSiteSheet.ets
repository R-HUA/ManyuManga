/**
 * E-Hentai 站点与账号设置面板：表站/里站切换、内置 WebView 登录（Cookie 自动同步原生请求）、
 * 手动导入 Cookie（ipb_member_id / ipb_pass_hash / igneous）、标签汉化词库状态。
 */
import web_webview from '@ohos.web.webview';
import { EhSettings } from '../../data/eh/EhSettings';
import { GallerySite } from '../../data/eh/EhNative';
import { SUB_CARD, PRIMARY, PRIMARY_SOFT, DANGER, DANGER_SOFT, STATUS_OK, TEXT_MAIN, TEXT_SUB, DIVIDER, ON_PRIMARY } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';
import { MangaRouteParams, ROUTE_BLOCK_RULES } from '../../common/Route';

const FORUMS_LOGIN_URL: string = 'https://forums.e-hentai.org/index.php?act=Login';
const FORUMS_HOME_URL: string = 'https://forums.e-hentai.org/';

@Component
export struct EhSiteSheet {
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @Consume('navPathStack') stack: NavPathStack;
  @State siteMode: string = GallerySite.E;
  @State cookieInput: string = '';
  @State notice: string = '';
  @State error: string = '';
  @State busy: boolean = false;
  @State webUrl: string = FORUMS_LOGIN_URL;
  @State tagLabel: string = '';
  @State loginLabel: string = '';
  @State showWebLogin: boolean = false;
  private controller: web_webview.WebviewController = new web_webview.WebviewController();
  close: () => void = (): void => {};
  @Prop embedded: boolean = false;

  aboutToAppear(): void {
    this.refreshStatus();
    this.cookieInput = EhSettings.cookie();
  }

  private refreshStatus(): void {
    this.siteMode = EhSettings.site();
    this.loginLabel = EhSettings.canUseEx()
      ? '已登录：里站已解锁（含可用 igneous）'
      : (EhSettings.hasLogin()
        ? '已登录账号，但缺少可用的 igneous，里站暂不可用（表站不受影响）'
        : '未登录：匿名访问表站（里站不可用）');
    this.tagLabel = EhSettings.tagTranslationLabel();
  }

  private async pickSite(mode: string): Promise<void> {
    this.error = '';
    try {
      await EhSettings.setSite(mode);
      this.refreshStatus();
      this.notice = mode === GallerySite.EX
        ? (EhSettings.exDowngraded() ? '已选里站，但未检测到账号或可用 igneous，将临时回退表站' : '已切换到 ExHentai 里站')
        : '已切换到 E-Hentai 表站';
      AppStorage.setOrCreate('sourceVersion', Date.now());
    } catch (e) {
      this.error = `${e instanceof Error ? e.message : '站点切换失败'}`;
    }
  }

  private async saveCookie(): Promise<void> {
    this.busy = true;
    this.error = '';
    this.notice = '';
    try {
      await EhSettings.saveCookie(this.cookieInput);
      this.refreshStatus();
      this.notice = this.cookieInput.trim() === '' ? '已清除 Cookie 与网页登录态' : 'Cookie 已保存并生效';
      AppStorage.setOrCreate('sourceVersion', Date.now());
    } catch (e) {
      this.error = `${e instanceof Error ? e.message : 'Cookie 保存失败'}`;
    } finally {
      this.busy = false;
    }
  }

  /** 完整退出：手动 Cookie + WebView 登录态一并清除。 */
  private async logout(): Promise<void> {
    this.busy = true;
    this.error = '';
    this.notice = '';
    try {
      await EhSettings.logout();
      this.cookieInput = '';
      this.refreshStatus();
      this.notice = '已退出登录：手动 Cookie 与网页登录态均已清除';
      AppStorage.setOrCreate('sourceVersion', Date.now());
    } catch (e) {
      this.error = `${e instanceof Error ? e.message : '退出失败'}`;
    } finally {
      this.busy = false;
    }
  }

  private webDone(): void {
    this.refreshStatus();
    this.notice = EhSettings.hasLogin()
      ? '已检测到登录状态，Cookie 将自动用于所有画廊请求'
      : '仍未检测到登录 Cookie，可继续在网页中完成登录后再次点击完成';
  }

  @Builder
  private SitePill(label: string, mode: string) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.siteMode === mode ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.siteMode === mode ? ON_PRIMARY : TEXT_MAIN)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 9, bottom: 9 })
      .borderRadius(16)
      .backgroundColor(this.siteMode === mode ? PRIMARY : SUB_CARD)
      .onClick(() => {
        this.pickSite(mode);
      })
  }

  @Builder
  private WebLinkButton(label: string, url: string) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Bold)
      .fontColor(PRIMARY)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(14)
      .backgroundColor(PRIMARY_SOFT)
      .onClick(() => {
        this.webUrl = url;
      })
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        if (!this.embedded) {
          Text('E-Hentai 站点与账号')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_MAIN)
            .width('100%')
        }

        Text(this.loginLabel)
          .fontSize(12)
          .fontColor(EhSettings.hasLogin() ? STATUS_OK : TEXT_SUB)
          .width('100%')

        // ── 站点切换 ──
        Row({ space: 8 }) {
          this.SitePill('E-Hentai 表站', GallerySite.E)
          this.SitePill('ExHentai 里站', GallerySite.EX)
        }
        .width('100%')

        if (this.siteMode === GallerySite.EX && EhSettings.exDowngraded()) {
          Text('里站需要账号 Cookie（含 igneous），未登录时自动回退表站以避免 Sad Panda 空响应。')
            .fontSize(11)
            .fontColor(TEXT_SUB)
            .width('100%')
        }

        // ── 内置 WebView 登录（按需展开） ──
        if (!this.showWebLogin) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.website'))
              .fontSize(16)
              .fontColor([PRIMARY])
            Text('打开内置网页登录（Cookie 自动同步）')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(PRIMARY)
          }
          .width('100%')
          .height(44)
          .justifyContent(FlexAlign.Center)
          .borderRadius(14)
          .backgroundColor(PRIMARY_SOFT)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
          .onClick(() => {
            this.showWebLogin = true;
          })
        } else {
          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('网页登录（Cookie 自动同步）')
                .fontSize(12)
                .fontColor(TEXT_SUB)
                .layoutWeight(1)
              this.WebLinkButton('登录页', FORUMS_LOGIN_URL)
              this.WebLinkButton('论坛首页', FORUMS_HOME_URL)
              Text('收起')
                .fontSize(12)
                .fontColor(TEXT_SUB)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(8)
                .backgroundColor(SUB_CARD)
                .onClick(() => {
                  this.showWebLogin = false;
                })
            }
            .width('100%')
            Web({ src: this.webUrl, controller: this.controller })
              .height(360)
              .width('100%')
              .borderRadius(14)
              .backgroundColor(SUB_CARD)
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .mixedMode(MixedMode.All)
            Text('完成')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(ON_PRIMARY)
              .textAlign(TextAlign.Center)
              .width('100%')
              .height(40)
              .borderRadius(20)
              .backgroundColor(PRIMARY)
              .onClick(() => {
                this.webDone();
                this.showWebLogin = false;
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }

        Divider().color(DIVIDER).width('100%')

        // ── 手动 Cookie 导入 ──
        Column({ space: 8 }) {
          Text('手动导入 Cookie（从浏览器复制 ipb_member_id / ipb_pass_hash / igneous）')
            .fontSize(12)
            .fontColor(TEXT_SUB)
            .width('100%')
          TextArea({ text: this.cookieInput, placeholder: 'ipb_member_id=…; ipb_pass_hash=…; igneous=…' })
            .height(88)
            .borderRadius(14)
            .backgroundColor(SUB_CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .onChange((s: string) => {
              this.cookieInput = s;
            })
          Row({ space: 10 }) {
            Text(this.busy ? '保存中…' : '保存 Cookie')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(ON_PRIMARY)
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(38)
              .borderRadius(19)
              .backgroundColor(PRIMARY)
              .opacity(this.busy ? 0.6 : 1.0)
              .onClick(() => {
                if (!this.busy) {
                  this.saveCookie();
                }
              })
            Text('退出登录')
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(DANGER)
              .textAlign(TextAlign.Center)
              .padding({ left: 20, right: 20 })
              .height(38)
              .borderRadius(19)
              .backgroundColor(DANGER_SOFT)
              .onClick(() => {
                if (!this.busy) {
                  this.logout();
                }
              })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Divider().color(DIVIDER).width('100%')

        // ── 标签汉化词库 ──
        Column({ space: 6 }) {
          Text('标签汉化词库')
            .fontSize(12)
            .fontColor(TEXT_SUB)
          Text(this.tagLabel)
            .fontSize(11)
            .fontColor(TEXT_SUB)
            .width('100%')
            .lineHeight(16)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        if (this.notice !== '') {
          Text(this.notice)
            .fontSize(12)
            .fontColor(STATUS_OK)
            .width('100%')
        }
        if (this.error !== '') {
          Text(this.error)
            .fontSize(12)
            .fontColor(DANGER)
            .width('100%')
        }

        Button('本源屏蔽规则', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY)
          .backgroundColor(PRIMARY_SOFT)
          .width('100%')
          .height(40)
          .onClick(() => {
            if (!this.embedded) {
              this.close();
            }
            this.stack.pushPathByName(ROUTE_BLOCK_RULES, { sourceId: 'eh' } as MangaRouteParams);
          })

        if (!this.embedded) {
          Text('收起')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_MAIN)
            .textAlign(TextAlign.Center)
            .width('100%')
            .height(42)
            .borderRadius(21)
            .backgroundColor(SUB_CARD)
            .onClick(() => {
              this.close();
            })
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 28 + this.bottomInset })
    }
    .width('100%')
    .scrollBar(BarState.Off)
  }
}
