import { ReaderOptions } from '../../data/ReaderOptions';
import { ReaderSettingsPanel } from './ReaderSettingsPanel';
import { ReaderDisplayPanel } from './ReaderDisplayPanel';
import { ReaderModePanel } from './ReaderModePanel';
import { HudButton } from './ReaderControls';
import { ReaderThumbStrip } from './ReaderThumbStrip';
import { PageThumbItem } from './ReaderImageItem';
import display from '@ohos.display';
import { IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { MASK_DARK, PRIMARY } from '../../common/Theme';
import { Chapter, ReadingProgress, ReaderMode } from '../../models/Models';

const ZOOM_MIN: number = 1;
const PANEL_BG: string = 'rgba(28,28,32,0.82)';
@Component
export struct ReaderHud {
  @Link options: ReaderOptions;
  @Link brightnessValue: number;
  @Link bgPaper: boolean;
  @Link preloadCount: number;
  @Link panel: 'none' | 'mode' | 'display' | 'settings';
  @Link hudVisible: boolean;
  goBack: () => void = (): void => {};
  @Link pages: Array<string>;
  @Link albumTitle: string;
  @Link currentPage: number;
  @Link zoomScale: number;
  resetZoom: (animated: boolean) => void = (animated: boolean): void => {};
  toggleBookmark: () => Promise<void> = async (): Promise<void> => {};
  @Link topSafeVp: number;
  @Link sliderDragging: boolean;
  private clampPage(page: number, total: number): number {
    if (total <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(page, total - 1));
  }
  @Link sliderValue: number;
  @Link scrambleId: number;
  @Link chapterIndex: number;
  goChapter: (delta: number) => void = (delta: number): void => {};
  @Link mode: ReaderMode;
  jumpToPage: (page: number) => void = (page: number): void => {};
  @Link chapters: Array<Chapter>;
  @Link sheetVisible: boolean;
  @Link bottomSafeVp: number;
  switchMode: (m: ReaderMode) => void = (m: ReaderMode): void => {};
  toggleBackground: (paper: boolean) => void = (paper: boolean): void => {};
  buildSpreads: () => void = (): void => {};
  scrollToPageDelayed: (page: number) => void = (page: number): void => {};
  persistOptions: () => Promise<void> = async (): Promise<void> => {};
  setPreload: (n: number) => void = (n: number): void => {};
  onHudTouch: (down: boolean) => void = (down: boolean): void => {};
  @Link bookmarks: Array<ReadingProgress>;

  build() {
    Column() {
      this.TopHud()
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          this.panel = 'none';
          this.hudVisible = false;
        })
      this.BottomHud()
    }
    .width('100%')
    .height('100%')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.onHudTouch(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onHudTouch(false);
      }
    })
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
  }

  @Builder
  private TopHud() {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([Color.White])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor('rgba(255,255,255,0.12)')
      .border({ width: 0.5, color: 'rgba(255,255,255,0.18)' })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => {
        this.goBack();
      })

      Column({ space: 2 }) {
        Text(this.chapterTitle())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.pages.length > 0) {
          Text(`${this.albumTitle ? this.albumTitle + ' · ' : ''}P.${Math.min(this.currentPage + 1, this.pages.length)}/${this.pages.length}`)
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.68)')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 缩放重置入口
      if (this.pages.length > 0 && this.zoomScale > ZOOM_MIN) {
        Text(`${this.zoomScale.toFixed(1)}x 复位`)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(PRIMARY)
          .onClick(() => {
            this.resetZoom(true);
          })
      }

      // 书签纯图标按钮
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.isCurrentPageBookmarked() ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
          .fontSize(17)
          .fontColor([this.isCurrentPageBookmarked() ? PRIMARY : Color.White])
      }
      .width(36)
      .height(36)
      .borderRadius(18)
      .backgroundColor(this.isCurrentPageBookmarked() ? 'rgba(58,122,254,0.22)' : 'rgba(255,255,255,0.12)')
      .border({ width: 0.5, color: this.isCurrentPageBookmarked() ? PRIMARY : 'rgba(255,255,255,0.18)' })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => {
        this.toggleBookmark();
      })

      if (this.pages.length > 0) {
        Text(this.modeShortLabel())
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(PRIMARY)
          .onClick(() => {
            this.panel = this.panel === 'mode' ? 'none' : 'mode';
          })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: this.topSafeVp + 8, bottom: 10 })
    .backgroundColor(MASK_DARK)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
  }

  @Builder
  private BottomHud() {
    Column({ space: 12 }) {
      if (this.panel === 'mode') {
        this.ModePanel()
      } else if (this.panel === 'display') {
        this.DisplayPanel()
      } else if (this.panel === 'settings') {
        this.SettingsPanel()
      }
      // 拖动进度条时显示目标页缩略图预览小窗
      if (this.sliderDragging && this.pages.length > 0) {
        Column({ space: 4 }) {
          PageThumbItem({
            photoId: this.currentChapterId(),
            filename: this.pages[this.clampPage(Math.round(this.sliderValue) - 1, this.pages.length)],
            scrambleId: this.scrambleId
          })
            .width(92)
            .height(128)
          Text(`P.${this.clampPage(Math.round(this.sliderValue) - 1, this.pages.length) + 1}`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .padding(6)
        .borderRadius(12)
        .backgroundColor(PANEL_BG)
        .border({ width: 0.5, color: 'rgba(255,255,255,0.16)' })
        .alignItems(HorizontalAlign.Center)
      }
      if (this.pages.length > 0) {
        ReaderThumbStrip({
          pages: this.pages,
          currentPage: this.currentPage,
          photoId: this.chapterId(),
          scrambleId: this.scrambleId,
          jumpToPage: (page: number): void => {
            this.jumpToPage(page);
          }
        })
      }
      // 进度滑动条 + 上一话/下一话
      if (this.pages.length > 0) {
        Row({ space: 10 }) {
          Button('上一话', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.chapterIndex > 0 ? Color.White : 'rgba(255,255,255,0.35)')
            .backgroundColor('rgba(255,255,255,0.12)')
            .height(34)
            .onClick(() => {
              this.goChapter(-1);
            })

          Column({ space: 2 }) {
            Slider({
              value: this.sliderDragging ? this.sliderValue
                : Math.min(this.currentPage + 1, Math.max(this.pages.length, 1)),
              min: 1,
              max: Math.max(this.pages.length, 1),
              step: 1,
              style: SliderStyle.OutSet,
              reverse: this.mode === 'rtl'
            })
              .selectedColor(PRIMARY)
              .trackColor('rgba(255,255,255,0.22)')
              .blockColor(Color.White)
              .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
              .width('100%')
              .height(28)
              .onChange((value: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                  this.sliderDragging = true;
                  this.sliderValue = value;
                } else {
                  this.sliderDragging = false;
                  if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    this.jumpToPage(Math.round(value) - 1);
                  }
                }
              })
            Text(`${this.sliderDragging ? Math.round(this.sliderValue) : Math.min(this.currentPage + 1, this.pages.length)} / ${this.pages.length}${this.mode === 'rtl' ? ' · 右翻' : ''}`)
              .fontSize(11)
              .fontColor('rgba(255,255,255,0.72)')
              .textAlign(TextAlign.Center)
              .width('100%')
          }
          .layoutWeight(1)

          Button('下一话', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.chapterIndex < this.chapters.length - 1
              ? Color.White : 'rgba(255,255,255,0.35)')
            .backgroundColor('rgba(255,255,255,0.12)')
            .height(34)
            .onClick(() => {
              this.goChapter(1);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      // 核心功能入口
      Row({ space: 10 }) {
        HudButton({
          symbol: $r('sys.symbol.list_bullet'),
          label: '目录',
          onTap: (): void => {
            this.sheetVisible = true;
          }
        })
        HudButton({
          symbol: $r('sys.symbol.rectangle_on_rectangle'),
          label: this.modeShortLabel(),
          active: this.panel === 'mode',
          onTap: (): void => {
            this.panel = this.panel === 'mode' ? 'none' : 'mode';
          }
        })
        HudButton({
          symbol: $r('sys.symbol.sun_max'),
          label: '画面',
          active: this.panel === 'display',
          onTap: (): void => {
            this.panel = this.panel === 'display' ? 'none' : 'display';
          }
        })
        HudButton({
          symbol: $r('sys.symbol.gearshape'),
          label: '设置',
          active: this.panel === 'settings',
          onTap: (): void => {
            this.panel = this.panel === 'settings' ? 'none' : 'settings';
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: this.bottomSafeVp + 12 })
    .backgroundColor(MASK_DARK)
    .backgroundBlurStyle(BlurStyle.BACKGROUND_THICK)
    .onClick(() => {
      // 阻断底栏点击穿透
    })
  }

  @Builder
  private ModePanel() {
    ReaderModePanel({
      mode: this.$mode,
      switchMode: (m: ReaderMode): void => this.switchMode(m)
    })
  }

  @Builder
  private DisplayPanel() {
    ReaderDisplayPanel({
      brightnessValue: this.$brightnessValue,
      bgPaper: this.$bgPaper,
      toggleBackground: (paper: boolean): void => this.toggleBackground(paper)
    })
  }

  @Builder
  private SettingsPanel() {
    ReaderSettingsPanel({
      options: this.$options,
      buildSpreads: (): void => this.buildSpreads(),
      scrollToPageDelayed: (page: number): void => this.scrollToPageDelayed(page),
      currentPage: this.$currentPage,
      persistOptions: (): Promise<void> => this.persistOptions(),
      preloadCount: this.$preloadCount,
      setPreload: (n: number): void => this.setPreload(n)
    })
  }

  private chapterId(): string {
    const ch: Chapter | undefined = this.chapters[this.chapterIndex];
    return ch === undefined ? '' : ch.id;
  }

  private chapterTitle(): string {
    const ch: Chapter | undefined = this.chapters[this.chapterIndex];
    if (ch !== undefined && ch.title !== '') {
      return ch.title;
    }
    return `第 ${this.chapterIndex + 1} 話`;
  }

  private modeShortLabel(): string {
    if (this.mode === 'vertical') {
      return '条漫';
    }
    if (this.mode === 'horizontal') {
      return '翻页';
    }
    if (this.mode === 'pagedVertical') { return '纵翻'; }
    if (this.mode === 'rtl') {
      return '右翻';
    }
    return '双页';
  }

  private isCurrentPageBookmarked(): boolean {
    const chId: string = this.currentChapterId();
    return this.bookmarks.some((b: ReadingProgress) => b.chapterId === chId && b.page === this.currentPage);
  }

  private currentChapterId(): string {
    const ch: Chapter | undefined = this.chapters[this.chapterIndex];
    return ch === undefined ? '' : ch.id;
  }
}
