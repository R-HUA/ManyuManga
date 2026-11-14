import image from '@ohos.multimedia.image';
import { sourceApi } from '../data/SourceApi';
import { memoryKey, takeFromMemory, publishIntoMemory, releasePagePixelMap } from '../data/PageCachePool';
import { isRequestCancelled, RequestAbortGroup } from '../util/RequestAbort';
import { SUB_CARD, TEXT_SUB } from './Theme';

/** 封面首次出现：200ms 淡入；消失不做动画，避免淡出期间仍引用已归还的位图。 */
export function coverFade(): TransitionEffect {
  return TransitionEffect.asymmetric(
    TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }),
    TransitionEffect.IDENTITY
  );
}

@Component
export struct SourceCover {
  @Prop @Watch('reload') url: string = '';
  @Prop @Watch('reload') sourceKey: string = '';
  @Prop deriveColor: boolean = false;
  @Prop radius: number = 12;
  onColor: (color: string) => void = (): void => {};
  @State bitmap: image.PixelMap | null = null;
  /** 只有占位图换成刚加载的新图时淡入；内存命中或封面换封面时直接显示。 */
  private fadeIn: boolean = false;
  private generation: number = 0;
  private signal: RequestAbortGroup = new RequestAbortGroup();

  aboutToAppear(): void {
    this.reload();
  }

  aboutToDisappear(): void {
    this.generation++;
    this.signal.abortAll();
    if (this.bitmap !== null) {
      releasePagePixelMap(this.bitmap);
      this.bitmap = null;
    }
  }

  /** 加载失败或地址为空时才回到占位。 */
  private clearBitmap(): void {
    const previous: image.PixelMap | null = this.bitmap;
    this.fadeIn = false;
    this.bitmap = null;
    if (previous !== null) {
      releasePagePixelMap(previous);
    }
  }

  private async reload(): Promise<void> {
    const ticket: number = ++this.generation;
    this.signal.abortAll();
    this.signal = new RequestAbortGroup();
    const signal: RequestAbortGroup = this.signal;
    if (this.url === '') {
      this.clearBitmap();
      return;
    }
    let pending: image.PixelMap | null = null;
    let fromMemory: boolean = false;
    try {
      const key: string = `cover/${memoryKey(this.sourceKey, this.url, 0, 300)}`;
      pending = await takeFromMemory(key);
      fromMemory = pending !== null;
      if (pending === null) {
        if (ticket !== this.generation || signal.aborted()) { return; }
        const bytes: ArrayBuffer = await sourceApi.fetchCover(this.sourceKey, this.url, signal);
        if (ticket !== this.generation || signal.aborted()) { return; }
        const source: image.ImageSource = image.createImageSource(bytes);
        let bitmap: image.PixelMap;
        try {
          bitmap = await source.createPixelMap({
            desiredSize: { width: 300, height: 400 },
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888
          });
        } finally {
          await source.release();
        }
        pending = publishIntoMemory(key, bitmap) ?? bitmap;
      }
      if (ticket !== this.generation || signal.aborted()) {
        return;
      }
      const bitmap: image.PixelMap = pending;
      if (this.deriveColor) {
        const buf: ArrayBuffer = new ArrayBuffer(300 * 400 * 4);
        await bitmap.readPixelsToBuffer(buf);
        const pixels: Uint8Array = new Uint8Array(buf);
        let red: number = 0;
        let green: number = 0;
        let blue: number = 0;
        let count: number = 0;
        for (let index: number = 0; index < pixels.length; index += 128) {
          red += pixels[index];
          green += pixels[index + 1];
          blue += pixels[index + 2];
          count++;
        }
        if (ticket !== this.generation) {
          return;
        }
        this.onColor(`rgba(${Math.round(red / count)},${Math.round(green / count)},${Math.round(blue / count)},0.16)`);
      }
      // 先让新图接替旧图，再归还旧图的缓存引用，避免闪白和 Image 引用已释放的 PixelMap。
      const previous: image.PixelMap | null = this.bitmap;
      this.fadeIn = !fromMemory && previous === null;
      this.bitmap = bitmap;
      pending = null;
      if (previous !== null) {
        releasePagePixelMap(previous);
      }
    } catch (_e) {
      if (isRequestCancelled(_e as Error)) {
        return;
      }
      if (ticket === this.generation) {
        this.clearBitmap();
      }
    } finally {
      if (pending !== null) {
        releasePagePixelMap(pending);
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.bitmap !== null) {
        Image(this.bitmap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .transition(this.fadeIn ? coverFade() : TransitionEffect.IDENTITY)
      } else {
        SymbolGlyph($r('sys.symbol.book'))
          .fontSize(26)
          .fontColor([TEXT_SUB])
      }
    }
    .width('100%')
    .aspectRatio(0.75)
    .backgroundColor(SUB_CARD)
    .borderRadius(this.radius)
    .clip(true)
  }
}
