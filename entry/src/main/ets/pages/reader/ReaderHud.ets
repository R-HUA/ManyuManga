import { clampPage } from '../../data/ReaderLayout';
import { ReaderOptions, ReaderSheetKind } from '../../data/ReaderOptions';
import { ReaderModePanel } from './ReaderModePanel';
import { ReaderPictureSheet } from './ReaderPictureSheet';
import { ReaderPrefsSheet } from './ReaderPrefsSheet';
import { HudButton } from './ReaderControls';
import { PageThumbItem } from './ReaderImageItem';
import { NEUTRAL_PROGRESS } from '../../common/Theme';
import { ReaderCatalogPanel } from './ReaderCatalogPanel';
import { BasicDataSource } from '../../common/DataSource';
import { EMPTY_MATERIAL } from '../../common/ImmersiveMaterials';
import { Chapter, ReaderMode, ReadingProgress } from '../../models/Models';

export type ReaderPanelKind = 'none' | 'progress' | 'index' | 'mode' | 'picture' | 'prefs';

/**
 * 原生气泡只在宿主设置材质，内部工具与面板不再叠加模糊背板。
 */
@Component
export struct ReaderHud {
  @Link panel: ReaderPanelKind;
  @Link pages: Array<string>;
  @Link currentPage: number;
  @Prop maxPanelHeight: number = 360;
  @Link sliderDragging: boolean;
  @Link sliderValue: number;
  @Link scrambleId: number;
  @Link chapterIndex: number;
  @Link chapters: Array<Chapter>;
  @Link mode: ReaderMode;
  @Link options: ReaderOptions;
  @Link brightnessValue: number;
  @Link bgPaper: boolean;
  @Link preloadCount: number;
  @Link bookmarks: Array<ReadingProgress>;
  chapterSource: BasicDataSource<Chapter> = new BasicDataSource<Chapter>();
  loadChapter: (chapterIdx: number, targetPage: number) => Promise<void> =
    async (_chapterIdx: number, _targetPage: number): Promise<void> => {};
  flushProgress: () => void = (): void => {};
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
      this.BottomHud()
    }
    .width('100%')
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.onHudTouch(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onHudTouch(false);
      }
    })
  }

  @Builder
  private BottomHud() {
    Column() {
      if (this.panel === 'index') {
        ReaderCatalogPanel({
          bookmarks: this.$bookmarks,
          chapters: this.$chapters,
          chapterIndex: this.$chapterIndex,
          pages: this.$pages,
          currentPage: this.$currentPage,
          scrambleId: this.$scrambleId,
          chapterSource: this.chapterSource,
          photoId: this.currentChapterId(),
          loadChapter: (chapterIdx: number, targetPage: number): Promise<void> => this.loadChapter(chapterIdx, targetPage),
          jumpToPage: (page: number): void => this.jumpToPage(page),
          flushProgress: (): void => this.flushProgress(),
          close: (): void => {
            this.panel = 'none';
          }
        })
          .width('100%')
          .height(Math.min(this.maxPanelHeight, 420))
          .padding({ left: 12, right: 12, top: 8 })
      } else if (this.panel !== 'none') {
        Scroll() {
          Column({ space: 10 }) {
          if (this.sliderDragging && this.pages.length > 0) { this.DragPreview() }
          if (this.panel === 'progress') {
            this.ProgressCard()
          } else if (this.panel === 'mode') {
            ReaderModePanel({
              mode: this.$mode,
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
              setPreload: (n: number): void => this.setPreload(n),
              openZoneEditor: (): void => this.openZoneEditor()
            })
          }
          }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 8 })
        }
        .width('100%')
        .constraintSize({ maxHeight: this.maxPanelHeight })
        .align(Alignment.TopStart).scrollBar(BarState.Off)
      }

      Row() {
        HudButton({
          symbol: $r('sys.symbol.list_bullet'),
          accessibilityLabel: '目录',
          active: this.panel === 'index',
          textColor: $r('sys.color.font_primary'),
          onTap: (): void => {
            this.panel = this.panel === 'index' ? 'none' : 'index';
          }
        })
        HudButton({
          symbol: $r('sys.symbol.slider_horizontal_2'),
          accessibilityLabel: '进度',
          active: this.panel === 'progress',
          textColor: $r('sys.color.font_primary'),
          onTap: (): void => {
            this.panel = this.panel === 'progress' ? 'none' : 'progress';
          }
        })
        HudButton({
          symbol: $r('sys.symbol.rectangle_on_rectangle'),
          accessibilityLabel: '阅读模式',
          active: this.panel === 'mode',
          textColor: $r('sys.color.font_primary'),
          onTap: (): void => {
            this.panel = this.panel === 'mode' ? 'none' : 'mode';
          }
        })
        HudButton({
          symbol: $r('sys.symbol.sun_max'),
          accessibilityLabel: '画面调节',
          active: this.panel === 'picture',
          textColor: $r('sys.color.font_primary'),
          onTap: (): void => {
            this.panel = this.panel === 'picture' ? 'none' : 'picture';
          }
        })
        HudButton({
          symbol: $r('sys.symbol.gearshape'),
          accessibilityLabel: '阅读设置',
          active: this.panel === 'prefs',
          textColor: $r('sys.color.font_primary'),
          onTap: (): void => {
            this.panel = this.panel === 'prefs' ? 'none' : 'prefs';
          }
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
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
        .fontColor($r('sys.color.font_primary'))
    }
    .padding(6)
    .borderRadius(12)
    .alignItems(HorizontalAlign.Center)
  }

  /** 进度浮卡：上一话图标 / 拖拽跳页 / 下一话图标，不挂内部 systemMaterial，避免在深色胶囊内出现浅灰材质块 */
  @Builder
  private ProgressCard() {
    Row({ space: 8 }) {
      this.ChapterStep($r('sys.symbol.chevron_left'), '上一话', this.chapterIndex > 0, -1)

      Slider({
        value: this.sliderDragging ? this.sliderValue
          : Math.min(this.currentPage + 1, Math.max(this.pages.length, 1)),
        min: 1,
        max: Math.max(this.pages.length, 1),
        step: 1,
        style: SliderStyle.InSet,
        reverse: this.mode === 'rtl'
      })
        .selectedColor(NEUTRAL_PROGRESS)
        .trackThickness(20)
        .showTips(false)
        .systemMaterial(EMPTY_MATERIAL)
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
        .fontColor($r('sys.color.font_secondary'))
        .constraintSize({ minWidth: 38 })
        .textAlign(TextAlign.Center)

      this.ChapterStep($r('sys.symbol.chevron_right'), '下一话', this.chapterIndex < this.chapters.length - 1, 1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 进度浮卡两侧的上一话/下一话图标按钮 */
  @Builder
  private ChapterStep(symbol: Resource, label: string, enabled: boolean, delta: number) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([enabled ? $r('sys.color.font_primary') : $r('sys.color.font_tertiary')])
    }
    .width(36)
    .height(36)
    .backgroundColor(Color.Transparent)
    .enabled(enabled)
    .accessibilityText(label)
    .onClick(() => {
      this.goChapter(delta);
    })
  }

  private currentChapterId(): string {
    const ch: Chapter | undefined = this.chapters[this.chapterIndex];
    return ch === undefined ? '' : ch.id;
  }
}
