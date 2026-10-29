import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { EhSiteSheet } from './EhSiteSheet';
import { BG } from '../../common/Theme';

/** E-Hentai 站点与账号：由半模态改为独立二级页，返回时浏览页在 onShown 中刷新站点标签。 */
@Component
export struct EhSitePage {
  @Consume('navPathStack') stack: NavPathStack;

  build() {
    HdsNavDestination() {
      EhSiteSheet({
        embedded: true,
        close: (): void => {
          this.stack.pop();
        }
      })
    }
    .titleBar({ content: { title: { mainTitle: '站点与账号' } }, style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(BG)
  }
}
