import image from '@ohos.multimedia.image';
import { loadPagePixelMap, releasePagePixelMap } from '../data/ImageDecode';
import { isRequestCancelled, RequestAbortGroup } from '../util/RequestAbort';
import { TEXT_SUB } from './Theme';

@Component
export struct PagePreview {
  @Prop chapter: string = '';
  @Prop filename: string = '';
  @Prop scramble: number = 0;
  @Prop thumbWidth: number = 240;
  @State bitmap: image.PixelMap | null = null;
  @State error: string = '';
  private active: boolean = true;
  private signal: RequestAbortGroup = new RequestAbortGroup();

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.signal.abortAll();
    if (this.bitmap !== null) {
      releasePagePixelMap(this.bitmap);
      this.bitmap = null;
    }
  }

  private async load(): Promise<void> {
    this.signal.abortAll();
    this.signal = new RequestAbortGroup();
    const signal: RequestAbortGroup = this.signal;
    try {
      const bitmap: image.PixelMap | null = await loadPagePixelMap(
        this.chapter, this.filename, this.scramble, this.thumbWidth, signal);
      if (!this.active || signal.aborted()) {
        if (bitmap !== null) {
          releasePagePixelMap(bitmap);
        }
        return;
      }
      this.bitmap = bitmap;
      if (bitmap === null) {
        this.error = '加载失败';
      }
    } catch (e) {
      if (isRequestCancelled(e as Error)) {
        return;
      }
      if (this.active) {
        this.error = (e as Error).message;
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
      } else if (this.error !== '') {
        Text('重试')
          .fontSize(11)
          .fontColor(TEXT_SUB)
          .onClick(() => {
            this.error = '';
            this.load();
          })
      } else {
        LoadingProgress().width(22).height(22)
      }
    }
    .width('100%')
    .height('100%')
  }
}
