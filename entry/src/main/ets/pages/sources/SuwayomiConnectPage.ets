import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { HDS_TITLE_STYLE } from '../../common/ImmersiveMaterials';
import { SuwayomiConnectSheet } from './SuwayomiConnectSheet';
import { SourceAuth, SourceInstance, sourceStore } from '../../data/Sources';
import { suwayomi } from '../../data/Suwayomi';
import { errorMessage } from '../../models/Models';
import { SourcePresentation, registrablePresentation } from '../../data/source/SourceCatalog';
import { BG } from '../../common/Theme';

/** Suwayomi 服务端连接配置：独立二级页，表单错误留在页内，连接成功后 Toast 并返回。 */
@Component
export struct SuwayomiConnectPage {
  @Consume('navPathStack') stack: NavPathStack;
  @State endpoint: string = '';
  @State name: string = '';
  @State user: string = '';
  @State password: string = '';
  @State authIndex: number = 0;
  @State error: string = '';
  @State busy: boolean = false;
  @State instance: string = '';

  aboutToAppear(): void {
    this.load();
  }

  async load(): Promise<void> {
    try {
      const current: SourceInstance | null = await sourceStore.connection();
      this.instance = current === null ? '' : current.id;
      this.endpoint = current === null ? '' : current.endpoint;
      this.name = current === null ? '' : current.name;
      this.authIndex = current !== null && current.auth === 'basic' ? 1 : (current !== null && current.auth === 'login' ? 2 : 0);
      this.error = '';
    } catch (e) {
      this.error = errorMessage(e as Error);
    }
  }

  async connect(replace: boolean = false): Promise<void> {
    if (this.busy) { return; }
    const current: SourceInstance | null = await sourceStore.connection();
    const base: string = this.endpoint.trim().replace(/\/+$/, '');
    if (!replace && current !== null && current.endpoint !== base) {
      this.getUIContext().showAlertDialog({
        title: '替换服务连接',
        message: '更换服务地址将停用原服务的扩展，并为新服务建立独立书源身份。已有书架与离线漫画会保留。',
        primaryButton: { value: '取消', action: (): void => {} },
        secondaryButton: { value: '替换并连接', action: (): void => { this.connect(true); } }
      });
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const modes: Array<SourceAuth> = ['none', 'basic', 'login'];
      const pres: SourcePresentation | null = registrablePresentation();
      await suwayomi.connect(
        this.endpoint,
        this.name.trim() || (pres === null ? 'Suwayomi' : pres.defaultName),
        modes[this.authIndex],
        this.user,
        this.password,
        this.instance,
        replace
      );
      this.password = '';
      this.getUIContext().getPromptAction().showToast({ message: '已连接 Suwayomi 书库' });
      this.stack.pop();
    } catch (e) {
      this.error = errorMessage(e as Error);
    } finally {
      this.busy = false;
    }
  }

  build() {
    HdsNavDestination() {
      SuwayomiConnectSheet({
        instance: this.instance,
        name: this.$name,
        endpoint: this.$endpoint,
        authIndex: this.$authIndex,
        user: this.$user,
        password: this.$password,
        error: this.$error,
        busy: this.$busy,
        connect: (): Promise<void> => this.connect()
      })
    }
    .titleBar({ content: { title: { mainTitle: 'Suwayomi 连接' } }, style: HDS_TITLE_STYLE,
      avoidLayoutSafeArea: true, enableComponentSafeArea: true })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(BG)
  }
}
