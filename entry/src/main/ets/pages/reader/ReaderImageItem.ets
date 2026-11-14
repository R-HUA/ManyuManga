import image from '@ohos.multimedia.image';
import { cropPageWhitespace } from '../../data/ImageDecode';
import { isPixelMapValid, loadPagePixelMap, PageLoadStage, releasePagePixelMap } from '../../data/ImageDecode';
import { isRequestCancelled, RequestAbortGroup } from '../../util/RequestAbort';
const PLACEHOLDER_BG: string = '#16161A';
/** 加载超过这个时长仍未出图，才在原图位置显示当前阶段文字。 */
const STAGE_HINT_DELAY_MS: number = 1000;

export function pageStageText(stage: string): string {
  if (stage === 'waiting') {
    return '等待加载';
  }
  if (stage === 'downloading') {
    return '正在下载';
  }
  if (stage === 'preparing') {
    return '正在准备图片';
  }
  return '';
}
const SCRAMBLE_DEFAULT: number = 220980;

@Component
export struct PageThumbItem {
  @Prop @Watch('onSrcChanged') photoId: string = '';
  @Prop @Watch('onSrcChanged') filename: string = '';
  @Prop @Watch('onSrcChanged') scrambleId: number = SCRAMBLE_DEFAULT;
  @State pixelMap: image.PixelMap | undefined = undefined;
  private token: number = 0;
  private signal: RequestAbortGroup = new RequestAbortGroup();

  aboutToAppear(): void {
    this.doLoad();
  }

  aboutToDisappear(): void {
    this.token++;
    this.signal.abortAll();
    this.releaseMap();
  }

  onSrcChanged(): void {
    this.doLoad();
  }

  private releaseMap(): void {
    const m: image.PixelMap | undefined = this.pixelMap;
    if (m !== undefined) {
      releasePagePixelMap(m);
      this.pixelMap = undefined;
    }
  }

  private async doLoad(): Promise<void> {
    if (this.photoId === '' || this.filename === '') {
      return;
    }
    const t: number = ++this.token;
    this.signal.abortAll();
    this.signal = new RequestAbortGroup();
    const signal: RequestAbortGroup = this.signal;
    try {
      const pm: image.PixelMap | null = await loadPagePixelMap(this.photoId, this.filename, this.scrambleId, 240, signal);
      if (t !== this.token) {
        if (pm !== null) {
          releasePagePixelMap(pm);
        }
        return;
      }
      if (pm === null) {
        this.releaseMap();
        return;
      }
      // 新图先接替，再归还旧图。
      const previous: image.PixelMap | undefined = this.pixelMap;
      this.pixelMap = pm;
      if (previous !== undefined) {
        releasePagePixelMap(previous);
      }
    } catch (e) {
      if (isRequestCancelled(e as Error)) {
        return;
      }
      if (t === this.token) {
        // 缩略图失败回到占位底色
        this.releaseMap();
      }
    }
  }

  build() {
    Stack() {
      if (this.pixelMap !== undefined) {
        Image(this.pixelMap)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      } else {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(PLACEHOLDER_BG)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(8)
    .clip(true)
  }
}

@Component
export struct ReaderImageItem {
  @Prop @Watch('onSourceChanged') photoId: string = '';
  @Prop @Watch('onSourceChanged') filename: string = '';
  @Prop @Watch('onSourceChanged') scrambleId: number = SCRAMBLE_DEFAULT;
  @Prop targetWidth: number = 0;
  /** true = 横向翻页整屏适配（ImageFit.Contain）；false = 纵向条漫整宽 */
  @Prop fitScreen: boolean = false;
  @Prop @Watch('onSourceChanged') cropWhite: boolean = false;
  /** 纸色画布：占位与失败提示改用浅色主题的系统 token。 */
  @Prop paper: boolean = false;
  onFailure: (filename: string, error: Error) => void = (): void => {};
  onMeasured: (filename: string, aspect: number) => void = (): void => {};
  @Prop @Watch('reportVisibility') active: boolean = true;
  onDisplayed: (chapter: string, filename: string, visible: boolean) => void = (): void => {};
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State loading: boolean = true;
  @State failed: boolean = false;
  @State aspect: number = 0.7;
  /** 当前真实阶段，只由 loadPagePixelMap 与裁白边节点推进。 */
  @State stage: string = '';
  /** 计时器只决定 1 秒后是否显示阶段文字，不推进阶段。 */
  @State stageVisible: boolean = false;
  private stageTimer: number = -1;
  private loadToken: number = 0;
  private inViewport: boolean = false;
  private displayed: boolean = false;
  private displayedChapter: string = '';
  private displayedFilename: string = '';
  private signal: RequestAbortGroup = new RequestAbortGroup();

  aboutToAppear(): void {
    this.doLoad();
  }

  aboutToDisappear(): void {
    this.onDisplayed(this.displayedChapter, this.displayedFilename, false);
    this.loadToken++;
    this.signal.abortAll();
    this.stopStageHint();
    this.releaseMap();
  }

  private stopStageHint(): void {
    if (this.stageTimer >= 0) {
      clearTimeout(this.stageTimer);
      this.stageTimer = -1;
    }
    this.stageVisible = false;
    this.stage = '';
  }

  private startStageHint(token: number): void {
    this.stopStageHint();
    this.stageTimer = setTimeout(() => {
      this.stageTimer = -1;
      if (token === this.loadToken && this.loading) {
        this.stageVisible = true;
      }
    }, STAGE_HINT_DELAY_MS);
  }

  private reportStage(token: number, stage: PageLoadStage): void {
    if (token === this.loadToken) {
      this.stage = stage;
    }
  }

  onSourceChanged(): void {
    this.doLoad();
  }

  private releaseMap(): void {
    const m: image.PixelMap | undefined = this.pixelMap;
    if (m !== undefined) {
      releasePagePixelMap(m);
      this.pixelMap = undefined;
    }
  }

  private async doLoad(): Promise<void> {
    this.displayed = false;
    this.onDisplayed(this.displayedChapter, this.displayedFilename, false);
    this.displayedChapter = this.photoId;
    this.displayedFilename = this.filename;
    if (this.photoId === '' || this.filename === '') {
      this.loading = false;
      this.failed = true;
      return;
    }
    const token: number = ++this.loadToken;
    this.signal.abortAll();
    this.signal = new RequestAbortGroup();
    const signal: RequestAbortGroup = this.signal;
    this.loading = true;
    this.failed = false;
    this.startStageHint(token);
    // 旧图保留到新图就位后再归还，不在请求开始时提前释放。
    try {
      let map: image.PixelMap | null = await loadPagePixelMap(
        this.photoId, this.filename, this.scrambleId, this.targetWidth, signal,
        (stage: PageLoadStage): void => this.reportStage(token, stage));
      if (token !== this.loadToken) {
        if (map !== null) {
          releasePagePixelMap(map);
        }
        return;
      }
      if (map === null) {
        this.stopStageHint();
        this.releaseMap();
        this.loading = false;
        this.failed = true;
        this.onFailure(this.filename, new Error('页面解码失败'));
        return;
      }
      if (this.cropWhite) {
        this.reportStage(token, 'preparing');
        const original: image.PixelMap = map;
        try { map = await cropPageWhitespace(original); }
        finally { releasePagePixelMap(original); }
        if (token !== this.loadToken) { await map.release(); return; }
      }
      if (!isPixelMapValid(map)) {
        releasePagePixelMap(map);
        throw new Error('图像尺寸无效，请重试');
      }
      const info: image.ImageInfo = map.getImageInfoSync();
      if (info.size === undefined || info.size.height <= 0) {
        releasePagePixelMap(map);
        throw new Error('图像尺寸无效，请重试');
      }
      this.aspect = info.size.width / info.size.height;
      this.onMeasured(this.filename, this.aspect);
      const previous: image.PixelMap | undefined = this.pixelMap;
      this.pixelMap = map;
      this.stopStageHint();
      this.loading = false;
      if (previous !== undefined) {
        releasePagePixelMap(previous);
      }
    } catch (e) {
      if (isRequestCancelled(e as Error)) {
        return;
      }
      if (token === this.loadToken) {
        this.stopStageHint();
        this.releaseMap();
        this.loading = false;
        this.failed = true;
        this.onFailure(this.filename, e as Error);
      }
    }
  }

  build() {
    Stack() {
      this.Content()
    }
    .width('100%')
    .height(this.fitScreen ? '100%' : 'auto')
    .onVisibleAreaChange([0, 0.01], (_visible: boolean, ratio: number): void => {
      this.inViewport = ratio > 0;
      this.reportVisibility();
    })
  }

  private reportVisibility(): void {
    this.onDisplayed(this.displayedChapter, this.displayedFilename, this.active && this.inViewport && this.displayed && !this.loading && !this.failed);
  }

  private imageComplete(token: number, chapter: string, filename: string): void {
    if (token !== this.loadToken || chapter !== this.photoId || filename !== this.filename) { return; }
    this.displayed = true;
    this.reportVisibility();
  }

  @Builder
  private DisplayImage(map: image.PixelMap, token: number, chapter: string, filename: string) {
    if (this.fitScreen) {
      Image(map).width('100%').height('100%').objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.Medium)
        .onComplete((): void => this.imageComplete(token, chapter, filename))
    } else {
      Image(map).width('100%').aspectRatio(this.aspect).objectFit(ImageFit.Fill)
        .interpolation(ImageInterpolation.Medium)
        .onComplete((): void => this.imageComplete(token, chapter, filename))
    }
  }

  @Builder
  private LoadingBody() {
    Column({ space: 8 }) {
      LoadingProgress().width(26).height(26).color($r('sys.color.font_tertiary'))
      if (this.stageVisible && pageStageText(this.stage) !== '') {
        Text(pageStageText(this.stage))
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
      }
    }
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private FailedBody() {
    Column({ space: 8 }) {
      Text('加载失败').fontSize(14).fontColor($r('sys.color.font_primary'))
      Text('点按重试（自动切换线路）').fontSize(12).fontColor($r('sys.color.font_secondary'))
    }
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private Placeholder(failed: boolean) {
    WithTheme({ colorMode: this.paper ? ThemeColorMode.LIGHT : ThemeColorMode.DARK }) {
      if (this.fitScreen) {
        Column() {
          if (failed) {
            this.FailedBody()
          } else {
            this.LoadingBody()
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          if (failed) {
            this.FailedBody()
          } else {
            this.LoadingBody()
          }
        }
        .width('100%')
        .aspectRatio(this.aspect)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .justifyContent(FlexAlign.Center)
      }
    }
  }

  @Builder
  private Content() {
    if (this.loading) {
      this.Placeholder(false)
    } else if (this.failed) {
      Column() {
        this.Placeholder(true)
      }
      .width('100%')
      .height(this.fitScreen ? '100%' : 'auto')
      .onClick(() => {
        this.doLoad();
      })
    } else if (this.pixelMap !== undefined) {
      this.DisplayImage(this.pixelMap, this.loadToken, this.displayedChapter, this.displayedFilename)
    }
  }
}
