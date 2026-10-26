import { EhSiteSheet } from '../eh/EhSiteSheet';

@Component
export struct SourceSettingsSheet {
  @Prop token: string = '';
  close: () => void = (): void => {};

  build() {
    Column() {
      if (this.token === 'eh.site') {
        EhSiteSheet({ close: this.close })
      }
    }
    .width('100%')
  }
}
