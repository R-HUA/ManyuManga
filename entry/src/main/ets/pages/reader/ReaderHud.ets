import { clampPage } from '../../data/ReaderLayout';
import { ReaderOptions, ReaderSheetKind } from '../../data/ReaderOptions';
import { ReaderModePanel } from './ReaderModePanel';
import { ReaderPictureSheet } from './ReaderPictureSheet';
import { ReaderPrefsSheet } from './ReaderPrefsSheet';
import { HudButton } from './ReaderControls';
import { PageThumbItem } from './ReaderImageItem';
import { PRIMARY, readerHudPalette } from '../../common/Theme';
import { Chapter, ReadingProgress, ReaderMode } from '../../models/Models';

const ZOOM_MIN: number = 1;

export type ReaderPanelKind = 'none' | 'progress' | 'mode' | 'picture' | 'prefs';

/**
 * 阅读器一级 HUD：参照华为阅读悬浮布局，顶部为独立悬浮圆钮与章节胶囊，
 * 底部为纯图标悬浮胶囊工具栏，点击进度/模式/画面/设置时在工具栏上方同宽展开同材质浮卡。
 */
@Component
export struct ReaderHud {
  @Link panel: ReaderPanelKind;
  @Link hudVisible: boolean;
  @Link pages: Array<string>;
  @Link albumTitle: string;
  @Link currentPage: number;
  @Link zoomScale: number;
  @Link topSafeVp: number;
  @Link bottomSafeVp: number;
  @Link sliderDragging: boolean;
  @Link sliderValue: number;
  @Link scrambleId: number;
  @Link chapterIndex: number;
  @Link chapters: Array<Chapter>;
  @Link mode: ReaderMode;
  @Link bookmarks: Array<ReadingProgress>;
  @Link options: ReaderOptions;
  @Link brightnessValue: number;
  @Link bgPaper: boolean;
  @Link preloadCount: number;
  goBack: () => void = (): void => {};
  resetZoom: (animated: boolean) => void = (animated: boolean): void => {};
  toggleBookmark: () => Promise<void> = async (): Promise<void> => {};
  goChapter: (delta: number) => void = (delta: number): void => {};
  jumpToPage: (page: number) => void = (page: number): void => {};
  switchMode: (m: ReaderMode) => void = (m: ReaderMode): void => {};
  openSheet: (kind: ReaderSheetKind) => void = (kind: ReaderSheetKind): void => {};
  onHudTouch: (down: boolean) => void = (down: boolean): void => {};
  buildSpreads: () => void = (): void => {};
  scrollToPageDelayed: (page: number) => void = (page: number): void => {};
  persistOptions: () => Promise<void> = async (): Promise<void> => {};
  toggleBackground: (paper: boolean) => void = (paper: boolean): void => {};
  setPreload: (n: number) => void = (n: number): void => {};
  openZoneEditor: () => void = (): void => {};

  build() {
    Column() {
      this.TopHud()
      Column()
        .width('100%')
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.Block)
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
          .fontSize(20)
          .fontColor([readerHudPalette(this.bgPaper).text])
      }
      .width(42)
      .height(42)
      .borderRadius(21)
      .backgroundColor(readerHudPalette(this.bgPaper).capsule)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .accessibilityText('返回')
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => {
        this.goBack();
      })

      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.chapterTitle())
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(readerHudPalette(this.bgPaper).text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.pages.length > 0) {
            Text(`${this.albumTitle} P.${Math.min(this.currentPage + 1, this.pages.length)}/${this.pages.length}`)
              .fontSize(11)
              .fontColor(readerHudPalette(this.bgPaper).textSub)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.pages.length > 0 && this.zoomScale > ZOOM_MIN) {
          Button(`${this.zoomScale.toFixed(1)}x 复位`, {
            type: ButtonType.Capsule,
            buttonStyle: ButtonStyleMode.EMPHASIZED,
            controlSize: ControlSize.SMALL
          })
            .onClick(() => {
              this.resetZoom(true);
            })
        }
      }
      .layoutWeight(1)
      .height(42)
      .padding({ left: 14, right: 14 })
      .borderRadius(21)
      .backgroundColor(readerHudPalette(this.bgPaper).capsule)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .alignItems(VerticalAlign.Center)

      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(this.isCurrentPageBookmarked() ? $r('sys.symbol.bookmark_fill') : $r('sys.symbol.bookmark'))
          .fontSize(19)
          .fontColor([this.isCurrentPageBookmarked() ? PRIMARY : readerHudPalette(this.bgPaper).text])
      }
      .width(42)
      .height(42)
      .borderRadius(21)
      .backgroundColor(readerHudPalette(this.bgPaper).capsule)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .accessibilityText(this.isCurrentPageBookmarked() ? '移除书签' : '添加书签')
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .onClick(() => {
        this.toggleBookmark();
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topSafeVp + 8, bottom: 8 })
  }

  @Builder
  private BottomHud() {
    Column({ space: 10 }) {
      if (this.sliderDragging && this.pages.length > 0) {
        this.DragPreview()
      }

      if (this.panel !== 'none') {
        Column() {
          if (this.panel === 'progress') {
            this.ProgressCard()
          } else if (this.panel === 'mode') {
            ReaderModePanel({
              mode: this.$mode,
              bgPaper: this.bgPaper,
              switchMode: (m: ReaderMode): void => this.switchMode(m)
            })
          } else if (this.panel === 'picture') {
            ReaderPictureSheet({
              options: this.$options,
              brightnessValue: this.$brightnessValue,
              bgPaper: this.$bgPaper,
              currentPage: this.$currentPage,
              buildSpreads: (): void => this.buildSpreads(),
              scrollToPageDelayed: (page: number): void => this.scrollToPageDelayed(page),
              persistOptions: (): Promise<void> => this.persistOptions(),
              toggleBackground: (paper: boolean): void => this.toggleBackground(paper)
            })
          } else if (this.panel === 'prefs') {
            ReaderPrefsSheet({
              options: this.$options,
              preloadCount: this.$preloadCount,
              bgPaper: this.bgPaper,
              setPreload: (n: number): void => this.setPreload(n),
              openZoneEditor: (): void => this.openZoneEditor()
            })
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .borderRadius(22)
        .backgroundColor(readerHudPalette(this.bgPaper).surface)
        .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      }

      Row() {
        HudButton({
          symbol: $r('sys.symbol.list_bullet'),
          accessibilityLabel: '目录',
          active: false,
          textColor: readerHudPalette(this.bgPaper).text,
          onTap: (): void => {
            this.panel = 'none';
            this.openSheet('index');
          }
        })
        HudButton({
          symbol: $r('sys.symbol.slider_horizontal_2'),
          accessibilityLabel: '进度',
          active: this.panel === 'progress',
          textColor: readerHudPalette(this.bgPaper).text,
          onTap: (): void => {
            this.panel = this.panel === 'progress' ? 'none' : 'progress';
          }
        })
        HudButton({
          symbol: $r('sys.symbol.rectangle_on_rectangle'),
          accessibilityLabel: '阅读模式',
          active: this.panel === 'mode',
          textColor: readerHudPalette(this.bgPaper).text,
          onTap: (): void => {
            this.panel = this.panel === 'mode' ? 'none' : 'mode';
          }
        })
        HudButton({
          symbol: $r('sys.symbol.sun_max'),
          accessibilityLabel: '画面调节',
          active: this.panel === 'picture',
          textColor: readerHudPalette(this.bgPaper).text,
          onTap: (): void => {
            this.panel = this.panel === 'picture' ? 'none' : 'picture';
          }
        })
        HudButton({
          symbol: $r('sys.symbol.gearshape'),
          accessibilityLabel: '阅读设置',
          active: this.panel === 'prefs',
          textColor: readerHudPalette(this.bgPaper).text,
          onTap: (): void => {
            this.panel = this.panel === 'prefs' ? 'none' : 'prefs';
          }
        })
      }
      .width('100%')
      .height(54)
      .padding({ left: 8, right: 8 })
      .borderRadius(27)
      .backgroundColor(readerHudPalette(this.bgPaper).capsule)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: this.bottomSafeVp + 12 })
    .onClick(() => {
      // 阻断底栏点击穿透
    })
  }

  /** 拖拽进度条时的目标页缩略浮窗 */
  @Builder
  private DragPreview() {
    Column({ space: 4 }) {
      PageThumbItem({
        photoId: this.currentChapterId(),
        filename: this.pages[clampPage(Math.round(this.sliderValue) - 1, this.pages.length)],
        scrambleId: this.scrambleId
      })
        .width(92)
        .height(128)
      Text(`${clampPage(Math.round(this.sliderValue) - 1, this.pages.length) + 1}`)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(readerHudPalette(this.bgPaper).text)
    }
    .padding(6)
    .borderRadius(12)
    .backgroundColor(readerHudPalette(this.bgPaper).surface)
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .alignItems(HorizontalAlign.Center)
  }

  /** 进度浮卡：上一话 / 拖拽跳页 / 下一话，不挂内部 systemMaterial，避免在深色胶囊内出现浅灰材质块 */
  @Builder
  private ProgressCard() {
    Row({ space: 8 }) {
      Button('上一话', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
        .fontColor(this.chapterIndex > 0 ? readerHudPalette(this.bgPaper).text : readerHudPalette(this.bgPaper).faint)
        .enabled(this.chapterIndex > 0)
        .onClick(() => {
          this.goChapter(-1);
        })

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
        .layoutWeight(1)
        .enabled(this.pages.length > 1)
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

      Text(`${this.sliderDragging ? Math.round(this.sliderValue)
        : Math.min(this.currentPage + 1, Math.max(this.pages.length, 1))}/${Math.max(this.pages.length, 1)}`)
        .fontSize(12)
        .fontColor(readerHudPalette(this.bgPaper).textSub)
        .constraintSize({ minWidth: 38 })
        .textAlign(TextAlign.Center)

      Button('下一话', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
        .fontColor(this.chapterIndex < this.chapters.length - 1
          ? readerHudPalette(this.bgPaper).text : readerHudPalette(this.bgPaper).faint)
        .enabled(this.chapterIndex < this.chapters.length - 1)
        .onClick(() => {
          this.goChapter(1);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  private chapterTitle(): string {
    const ch: Chapter | undefined = this.chapters[this.chapterIndex];
    if (ch !== undefined && ch.title !== '') {
      return ch.title;
    }
    return `第 ${this.chapterIndex + 1} 話`;
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
