import { catalogPanelHeight, clampPage } from '../../data/ReaderLayout';
import { ReaderOptions, ReaderSheetKind } from '../../data/ReaderOptions';
import { ReaderModePanel, readerModeIcon } from './ReaderModePanel';
import { ReaderPictureSheet } from './ReaderPictureSheet';
import { ReaderPrefsSheet } from './ReaderPrefsSheet';
import { HudButton } from './ReaderControls';
import { PageThumbItem } from './ReaderImageItem';
import { NEUTRAL_PROGRESS } from '../../common/Theme';
import { ReaderCatalogPanel } from './ReaderCatalogPanel';
import { BasicDataSource } from '../../common/DataSource';
import { EMPTY_MATERIAL, READER_BAR_BACKING, READER_BAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { readerModeLabel } from '../../data/ReaderModeCycle';
import { Chapter, ReaderMode, ReadingProgress } from '../../models/Models';

export type ReaderPanelKind = 'none' | 'progress' | 'index' | 'mode' | 'picture' | 'prefs';

/**
 * 阅读器底栏：贴底固定，两行结构——上行为当前入口的内容（目录 / 进度 / 设置），下行为带文字的入口。
 * 整栏一层沉浸光感材质＋深色半透明底（上行面板与下行入口共用），配色由宿主外层 WithTheme(DARK) 固定为深色；
 * 内部面板不再叠加材质或模糊背板。
 * 「模式」不展开面板，点按即按固定顺序循环切换，图标随当前模式变化。
 */
@Component
export struct ReaderHud {
  @Link panel: ReaderPanelKind;
  @Link pages: Array<string>;
  @Link currentPage: number;
  @Prop maxPanelHeight: number = 360;
  @Prop bottomInset: number = 0;
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
  @Link tapTurn: boolean;
  setTapTurn: (on: boolean) => void = (_on: boolean): void => {};
  @Link bookmarks: Array<ReadingProgress>;
  chapterSource: BasicDataSource<Chapter> = new BasicDataSource<Chapter>();
  loadChapter: (chapterIdx: number, targetPage: number) => Promise<void> =
    async (_chapterIdx: number, _targetPage: number): Promise<void> => {};
  flushProgress: () => void = (): void => {};
  goChapter: (delta: number) => void = (delta: number): void => {};
  jumpToPage: (page: number) => void = (page: number): void => {};
  switchMode: (m: ReaderMode) => void = (m: ReaderMode): void => {};
  cycleMode: () => void = (): void => {};
  openSheet: (kind: ReaderSheetKind) => void = (kind: ReaderSheetKind): void => {};
  onHudTouch: (down: boolean) => void = (down: boolean): void => {};
  buildSpreads: () => void = (): void => {};
  scrollToPageDelayed: (page: number) => void = (page: number): void => {};
  persistOptions: () => Promise<void> = async (): Promise<void> => {};
  toggleBackground: (paper: boolean) => void = (paper: boolean): void => {};
  setPreload: (n: number) => void = (n: number): void => {};
  openZoneEditor: () => void = (): void => {};

  /** 进度两侧按钮容易误触，明确目标章节后再执行切换。 */
  private confirmChapter(delta: number): void {
    const chapter: Chapter | undefined = this.chapters[this.chapterIndex + delta];
    if (chapter === undefined) { return; }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.switch_chapter_title'),
      message: $r('app.string.switch_chapter_message', chapter.title || `第 ${this.chapterIndex + delta + 1} 章`),
      primaryButton: { value: $r('app.string.cancel_action'), action: (): void => {} },
      secondaryButton: { value: $r('app.string.switch_chapter_action'), action: (): void => this.goChapter(delta) }
    });
  }

  build() {
    // 外层只挂材质；内层垫深色半透明底，材质未生效时栏也不会透明。
    Column() {
      Column() {
        this.BottomHud()
      }
      .width('100%')
      .padding({ bottom: this.bottomInset })
      .backgroundColor(READER_BAR_BACKING)
    }
    .width('100%')
    .systemMaterial(READER_BAR_MATERIAL)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.onHudTouch(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onHudTouch(false);
      }
    })
  }

  private settingsOpen(): boolean {
    return this.panel === 'prefs' || this.panel === 'picture' || this.panel === 'mode';
  }

  private togglePanel(kind: ReaderPanelKind): void {
    this.switchPanel(this.panel === kind ? 'none' : kind);
  }

  /** 面板切换：容器高度与内容淡入淡出在同一段动画里完成，避免高度硬跳。 */
  private switchPanel(next: ReaderPanelKind): void {
    if (next === this.panel) {
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.FastOutSlowIn }, () => {
      this.panel = next;
    });
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ top: 4 })
  }

  /** 设置：阅读模式、画面与阅读偏好集中在一处。 */
  @Builder
  private SettingsPanel() {
    Column({ space: 10 }) {
      this.SectionTitle('阅读模式')
      ReaderModePanel({
        mode: this.$mode,
        switchMode: (m: ReaderMode): void => this.switchMode(m)
      })
      Divider().strokeWidth('1px').color($r('sys.color.comp_divider'))
      this.SectionTitle('画面')
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
      Divider().strokeWidth('1px').color($r('sys.color.comp_divider'))
      this.SectionTitle('阅读')
      ReaderPrefsSheet({
        options: this.$options,
        preloadCount: this.$preloadCount,
        setPreload: (n: number): void => this.setPreload(n),
        tapTurn: this.$tapTurn,
        setTapTurn: (on: boolean): void => this.setTapTurn(on),
        openZoneEditor: (): void => this.openZoneEditor()
      })
    }
    .width('100%')
  }

  @Builder
  private BottomHud() {
    Column() {
      if (this.panel === 'index') {
        ReaderCatalogPanel({
          bookmarks: this.$bookmarks,
          chapters: this.$chapters,
          chapterIndex: this.$chapterIndex,
          chapterSource: this.chapterSource,
          loadChapter: (chapterIdx: number, targetPage: number): Promise<void> => this.loadChapter(chapterIdx, targetPage),
          flushProgress: (): void => this.flushProgress(),
          close: (): void => {
            this.switchPanel('none');
          }
        })
          .width('100%')
          .height(catalogPanelHeight(this.chapters.length, this.bookmarks.length, Math.min(this.maxPanelHeight, 420)))
          .padding({ left: 12, right: 12, top: 8 })
          .transition(TransitionEffect.OPACITY)
      } else if (this.panel !== 'none') {
        Scroll() {
          Column({ space: 10 }) {
            if (this.sliderDragging && this.pages.length > 0) { this.DragPreview() }
            if (this.panel === 'progress') {
              Column() {
                this.ProgressCard()
              }
              .width('100%')
              .transition(TransitionEffect.OPACITY)
            } else if (this.settingsOpen()) {
              Column() {
                this.SettingsPanel()
              }
              .width('100%')
              .transition(TransitionEffect.OPACITY)
            }
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 4 })
        }
        .width('100%')
        .constraintSize({ maxHeight: this.maxPanelHeight })
        .align(Alignment.TopStart).scrollBar(BarState.Off)
        .transition(TransitionEffect.OPACITY)
      }

      Row() {
        HudButton({
          symbol: $r('sys.symbol.list_bullet'),
          label: '目录',
          active: this.panel === 'index',
          onTap: (): void => { this.togglePanel('index'); }
        })
        HudButton({
          symbol: $r('sys.symbol.slider_horizontal_2'),
          label: '进度',
          active: this.panel === 'progress',
          onTap: (): void => { this.togglePanel('progress'); }
        })
        HudButton({
          symbol: readerModeIcon(this.mode),
          label: '模式',
          accessibilityLabel: `阅读模式：${readerModeLabel(this.mode)}，点按切换`,
          onTap: (): void => { this.cycleMode(); }
        })
        HudButton({
          symbol: $r('sys.symbol.gearshape'),
          label: '设置',
          active: this.settingsOpen(),
          onTap: (): void => { this.switchPanel(this.settingsOpen() ? 'none' : 'prefs'); }
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
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
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
      this.confirmChapter(delta);
    })
  }

  private currentChapterId(): string {
    const ch: Chapter | undefined = this.chapters[this.chapterIndex];
    return ch === undefined ? '' : ch.id;
  }
}
