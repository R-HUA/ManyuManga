import image from '@ohos.multimedia.image';
import { loadPagePixelMap, releasePagePixelMap } from '../data/ImageDecode';
import { isRequestCancelled, RequestAbortGroup } from '../util/RequestAbort';
import { TEXT_SUB } from './Theme';

@Component
export struct PagePreview {
  @Prop @Watch('load') chapter: string = '';
  @Prop @Watch('load') filename: string = '';
  @Prop @Watch('load') scramble: number = 0;
  @Prop @Watch('load') thumbWidth: number = 240;
  @Prop @Watch('onActiveChanged') active: boolean = true;
  onOpen: () => void = (): void => {};
  @State bitmap: image.PixelMap | null = null;
  @State error: string = '';
  private attached: boolean = false;
  private generation: number = 0;
  private signal: RequestAbortGroup = new RequestAbortGroup();

  aboutToAppear(): void {
    this.attached = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.attached = false;
    this.generation++;
    this.signal.abortAll();
    if (this.bitmap !== null) {
      releasePagePixelMap(this.bitmap);
      this.bitmap = null;
    }
  }

  private onActiveChanged(): void {
    if (!this.active) {
      this.generation++;
      this.signal.abortAll();
    } else if (this.attached && this.bitmap === null) {
      this.load();
    }
  }

  private async load(): Promise<void> {
    const ticket: number = ++this.generation;
    this.signal.abortAll();
    this.signal = new RequestAbortGroup();
    const signal: RequestAbortGroup = this.signal;
    this.error = '';
    if (this.bitmap !== null) {
      releasePagePixelMap(this.bitmap);
      this.bitmap = null;
    }
    if (!this.active || !this.attached) { return; }
    try {
      const bitmap: image.PixelMap | null = await loadPagePixelMap(
        this.chapter, this.filename, this.scramble, this.thumbWidth, signal);
      if (!this.active || !this.attached || ticket !== this.generation || signal.aborted()) {
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
      if (this.active && ticket === this.generation && !signal.aborted()) {
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
          .onClick((): void => this.onOpen())
      } else if (this.error !== '') {
        Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .constraintSize({ minWidth: 40, minHeight: 40 })
          .fontSize(12)
          .fontColor(TEXT_SUB)
          .onClick(() => {
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
