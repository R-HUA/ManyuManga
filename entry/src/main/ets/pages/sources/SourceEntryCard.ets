import { SourceEntry, sourceStore } from '../../data/Sources';
import { EhSettings } from '../../data/eh/EhSettings';
import { GallerySite } from '../../data/eh/EhNative';
import {
  SourceAction,
  SourcePresentation,
  presentationFor,
  sourceActions
} from '../../data/source/SourceCatalog';
import { MangaRouteParams } from '../../common/Route';
import { errorMessage } from '../../models/Models';
import { DANGER, TEXT_MAIN, TEXT_SUB } from '../../common/Theme';

/**
 * 图源平铺列表行：无卡片底色、无左侧图标、无行内按钮，整行点击直接进入对应图源。
 */
@Component
export struct SourceEntryCard {
  @Consume('navPathStack') stack: NavPathStack;
  @Prop source: SourceEntry = new SourceEntry();
  @Prop busy: boolean = false;
  @Prop settingsOnly: boolean = false;
  @Prop showSettings: boolean = false;
  @State actionsVisible: boolean = false;
  reportError: (message: string) => void = (_message: string): void => {};
  connectSource: (source: SourceEntry) => void = (_source: SourceEntry): void => {};
  openSettings: (entry: SourceEntry) => void = (_entry: SourceEntry): void => {};
  importLocal: () => void = (): void => {};
  reloadSources: () => void = (): void => {};

  private presentation(): SourcePresentation {
    return presentationFor(this.source.kind);
  }

  private displayName(): string {
    return this.source.kind === 'eh' && this.source.name === 'E-Hentai / ExHentai' ?
      (EhSettings.effectiveSite() === GallerySite.EX ? 'ExHentai' : 'E-Hentai') : this.source.name;
  }

  /** 主动作：点击整行直接进入该图源的发现页或浏览页 */
  onPrimaryBrowse(): void {
    if (this.settingsOnly || !this.source.enabled) {
      this.openSourceConfig();
      return;
    }
    const actions: Array<SourceAction> = sourceActions(this.source);
    const primaryAction: SourceAction | undefined = actions.find((a: SourceAction) => a.primary) ?? actions[0];
    if (primaryAction !== undefined) {
      this.run(primaryAction);
    }
  }

  secondaryActions(): Array<SourceAction> {
    return sourceActions(this.source).filter((action: SourceAction): boolean => !action.primary && action.kind !== 'import');
  }

  private openSourceConfig(): void {
    const actions: Array<SourceAction> = this.secondaryActions();
    if (actions.length === 1) {
      this.run(actions[0]);
    } else {
      this.actionsVisible = true;
    }
  }

  run(action: SourceAction): void {
    if (action.requiresEnabled && (!this.source.enabled || this.busy)) {
      return;
    }
    if (action.kind === 'import') {
      this.importLocal();
      return;
    }
    if (action.kind === 'settings') {
      this.openSettings(this.source);
      return;
    }
    if (action.kind === 'connect') {
      this.connectSource(this.source);
      return;
    }
    if (action.kind === 'remove') {
      this.confirmRemove();
      return;
    }
    if (action.route !== '') {
      this.stack.pushPathByName(action.route, { sourceId: this.source.id } as MangaRouteParams);
    }
  }

  private confirmRemove(): void {
    this.getUIContext().showAlertDialog({
      title: '移除书源',
      message: `确定移除「${this.source.name}」吗？书架中的漫画、阅读记录与离线文件均会保留。`,
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '移除',
        fontColor: DANGER,
        action: (): void => {
          sourceStore.remove(this.source.id).then((): void => {
            this.reloadSources();
          }).catch((e: Error) => {
            this.reportError(errorMessage(e));
            this.reloadSources();
          });
        }
      }
    });
  }

  build() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(this.displayName())
          .fontColor(this.source.enabled ? TEXT_MAIN : TEXT_SUB)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (!this.source.enabled) {
          Text('已停用').fontColor(TEXT_SUB).fontSize(12)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([TEXT_SUB])
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.99 })
    .onClick(() => this.onPrimaryBrowse())
  }

}
