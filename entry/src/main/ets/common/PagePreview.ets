import image from '@ohos.multimedia.image';
import { loadPagePixelMap, releasePagePixelMap } from '../data/ImageDecode';
import { TEXT_SUB } from './Theme';
@Component
export struct PagePreview {
  @Prop chapter: string = '';
  @Prop filename: string = '';
  @Prop scramble: number = 0;
  @State bitmap: image.PixelMap | null = null;
  @State error: string = '';
  private active: boolean = true;
  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { this.active = false; if (this.bitmap !== null) { releasePagePixelMap(this.bitmap); } }
  private async load(): Promise<void> {
    try {
      const bitmap: image.PixelMap | null = await loadPagePixelMap(this.chapter, this.filename, this.scramble, 480);
      if (!this.active) { if (bitmap !== null) { releasePagePixelMap(bitmap); } return; }
      this.bitmap = bitmap;
      if (bitmap === null) { this.error = '预览加载失败'; }
    } catch (e) { if (this.active) { this.error = (e as Error).message; } }
  }
  build() {
    Column() {
      if (this.bitmap !== null) { Image(this.bitmap).width('100%').objectFit(ImageFit.Contain) }
      else if (this.error !== '') { Text(this.error).fontColor(TEXT_SUB).padding(24) }
      else { LoadingProgress().width(32).height(32).margin(32) }
    }.width('100%')
  }
}
