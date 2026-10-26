import image from '@ohos.multimedia.image';
import { cropPageWhitespace } from '../../data/ImageDecode';
import { isPixelMapValid, loadPagePixelMap, releasePagePixelMap } from '../../data/ImageDecode';
import { isRequestCancelled, RequestAbortGroup } from '../../util/RequestAbort';
const PLACEHOLDER_BG: string = '#16161A';
const FAILED_BG: string = '#201619';
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
    this.releaseMap();
    try {
      const pm: image.PixelMap | null = await loadPagePixelMap(this.photoId, this.filename, this.scrambleId, 240, signal);
      if (t !== this.token) {
        if (pm !== null) {
          releasePagePixelMap(pm);
        }
        return;
      }
      this.pixelMap = pm === null ? undefined : pm;
    } catch (e) {
      if (isRequestCancelled(e as Error)) {
        return;
      }
      // 缩略图失败保持占位底色
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
  onFailure: (filename: string, error: Error) => void = (): void => {};
  onMeasured: (filename: string, aspect: number) => void = (): void => {};
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State loading: boolean = true;
  @State failed: boolean = false;
  @State aspect: number = 0.7;
  private loadToken: number = 0;
  private signal: RequestAbortGroup = new RequestAbortGroup();

  aboutToAppear(): void {
    this.doLoad();
  }

  aboutToDisappear(): void {
    this.loadToken++;
    this.signal.abortAll();
    this.releaseMap();
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
    this.releaseMap();
    try {
      let map: image.PixelMap | null = await loadPagePixelMap(
        this.photoId, this.filename, this.scrambleId, this.targetWidth, signal);
      if (token !== this.loadToken) {
        if (map !== null) {
          releasePagePixelMap(map);
        }
        return;
      }
      if (map === null) {
        this.loading = false;
        this.failed = true;
        this.onFailure(this.filename, new Error('页面解码失败'));
        return;
      }
      if (this.cropWhite) {
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
      this.pixelMap = map;
      this.loading = false;
    } catch (e) {
      if (isRequestCancelled(e as Error)) {
        return;
      }
      if (token === this.loadToken) {
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
  }

  @Builder
  private Content() {
    if (this.loading) {
      if (this.fitScreen) {
        Column() {
          LoadingProgress().width(26).height(26).color('rgba(255,255,255,0.45)')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(PLACEHOLDER_BG)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          LoadingProgress().width(26).height(26).color('rgba(255,255,255,0.45)')
        }
        .width('100%')
        .aspectRatio(this.aspect)
        .backgroundColor(PLACEHOLDER_BG)
        .justifyContent(FlexAlign.Center)
      }
    } else if (this.failed) {
      if (this.fitScreen) {
        Column({ space: 8 }) {
          Text('加载失败').fontSize(14).fontColor('rgba(255,255,255,0.85)')
          Text('点按重试（自动切换线路）').fontSize(11).fontColor('rgba(255,255,255,0.5)')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(FAILED_BG)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.doLoad();
        })
      } else {
        Column({ space: 8 }) {
          Text('加载失败').fontSize(14).fontColor('rgba(255,255,255,0.85)')
          Text('点按重试（自动切换线路）').fontSize(11).fontColor('rgba(255,255,255,0.5)')
        }
        .width('100%')
        .aspectRatio(this.aspect)
        .backgroundColor(FAILED_BG)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.doLoad();
        })
      }
    } else if (this.pixelMap !== undefined) {
      if (this.fitScreen) {
        Image(this.pixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.Medium)
      } else {
        Image(this.pixelMap)
          .width('100%')
          .aspectRatio(this.aspect)
          .objectFit(ImageFit.Fill)
          .interpolation(ImageInterpolation.Medium)
      }
    }
  }
}
