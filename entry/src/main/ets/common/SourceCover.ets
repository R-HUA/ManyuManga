import image from '@ohos.multimedia.image';
import { sourceApi } from '../data/SourceApi';
import { CARD, TEXT_SUB } from './Theme';

@Component
export struct SourceCover {
  @Prop @Watch('reload') url: string = '';
  @Prop deriveColor: boolean = false;
  onColor: (color: string) => void = (): void => {};
  @State bitmap: image.PixelMap | null = null;
  private generation: number = 0;
  aboutToAppear(): void { this.reload(); }
  aboutToDisappear(): void {
    this.generation++;
    if (this.bitmap !== null) { this.bitmap.release(); this.bitmap = null; }
  }
  private async reload(): Promise<void> {
    const ticket: number = ++this.generation;
    const previous: image.PixelMap | null = this.bitmap;
    this.bitmap = null;
    if (previous !== null) { await previous.release(); }
    if (ticket !== this.generation) { return; }
    if (this.url === '') { return; }
    let pending: image.PixelMap | null = null;
    try {
      const bytes: ArrayBuffer = await sourceApi.fetchBytes(this.url);
      const source: image.ImageSource = image.createImageSource(bytes);
      let bitmap: image.PixelMap;
      try { bitmap = await source.createPixelMap({ desiredSize: { width: 300, height: 400 }, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 }); }
      finally { await source.release(); }
      pending = bitmap;
      if (ticket !== this.generation) { return; }
      if (this.deriveColor) {
        const bytes: ArrayBuffer = new ArrayBuffer(300 * 400 * 4);
        await bitmap.readPixelsToBuffer(bytes);
        const pixels: Uint8Array = new Uint8Array(bytes);
        let red: number = 0; let green: number = 0; let blue: number = 0; let count: number = 0;
        for (let index: number = 0; index < pixels.length; index += 128) {
          red += pixels[index]; green += pixels[index + 1]; blue += pixels[index + 2]; count++;
        }
        if (ticket !== this.generation) { return; }
        this.onColor(`rgba(${Math.round(red / count)},${Math.round(green / count)},${Math.round(blue / count)},0.22)`);
      }
      this.bitmap = bitmap;
      pending = null;
    } catch (e) {
      if (ticket === this.generation) { this.bitmap = null; }
    } finally {
      if (pending !== null) { await pending.release(); }
    }
  }
  build() {
    Stack() {
      if (this.bitmap !== null) { Image(this.bitmap).width('100%').height('100%').objectFit(ImageFit.Cover) }
      else { SymbolGlyph($r('sys.symbol.book')).fontSize(32).fontColor([TEXT_SUB]) }
    }.width('100%').aspectRatio(0.75).backgroundColor(CARD).borderRadius(12).clip(true)
  }
}
