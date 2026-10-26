import { IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { SourceEntry, copySource, sourceStore } from '../../data/Sources';
import { SourceCapabilities, capabilitiesFor } from '../../data/source/SourceContracts';
import {
  SourceAction,
  SourcePresentation,
  presentationFor,
  sourceActions
} from '../../data/source/SourceCatalog';
import { sourceGlyph } from '../../common/SourceGlyph';
import { MangaRouteParams, ROUTE_BLOCK_RULES, ROUTE_JM_SETTINGS, ROUTE_SEARCH } from '../../common/Route';
import { errorMessage } from '../../models/Models';
import { IconCircleButton } from '../../common/Components';
import {
  CARD, SUB_CARD, PRIMARY, PRIMARY_SOFT, ACCENT, ACCENT_SOFT, DANGER,
  STATUS_OK, TEXT_MAIN, TEXT_SUB, DIVIDER
} from '../../common/Theme';

@Component
export struct SourceEntryCard {
  @Consume('navPathStack') stack: NavPathStack;
  @Prop source: SourceEntry = new SourceEntry();
  @Prop busy: boolean = false;
  reportError: (message: string) => void = (_message: string): void => {};
  connectSource: (source: SourceEntry) => void = (_source: SourceEntry): void => {};
  openSettings: (entry: SourceEntry) => void = (_entry: SourceEntry): void => {};
  importLocal: () => void = (): void => {};
  reloadSources: () => void = (): void => {};

  private caps(): SourceCapabilities {
    return capabilitiesFor(this.source.kind);
  }

  private presentation(): SourcePresentation {
    return presentationFor(this.source.kind);
  }

  /** 主动作：点击整行直接进入该图源的发现广场或检索页 */
  private onPrimaryBrowse(): void {
    if (!this.source.enabled) {
      this.openSourceConfig();
      return;
    }
    const actions: Array<SourceAction> = sourceActions(this.source);
    const primaryAction: SourceAction | undefined = actions.find((a: SourceAction) => a.primary) ?? actions[0];
    if (primaryAction !== undefined) {
      this.run(primaryAction);
    }
  }

  /** 次动作：点击齿轮按钮进入节点/账号/连接设置 */
  private openSourceConfig(): void {
    if (this.source.kind === 'jm') {
      this.stack.pushPathByName(ROUTE_JM_SETTINGS, {} as MangaRouteParams);
    } else if (this.source.kind === 'eh') {
      this.openSettings(this.source);
    } else if (this.source.kind === 'suwayomi') {
      this.connectSource(this.source);
    } else if (this.source.kind === 'local') {
      this.stack.pushPathByName(ROUTE_BLOCK_RULES, { sourceId: this.source.id } as MangaRouteParams);
    }
  }

  private run(action: SourceAction): void {
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
    if (action.kind === 'search') {
      this.stack.pushPathByName(ROUTE_SEARCH, { sourceId: this.source.id } as MangaRouteParams);
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
          sourceStore.remove(this.source.id).catch((e: Error) => {
            this.reportError(errorMessage(e));
            this.reloadSources();
          });
        }
      }
    });
  }

  build() {
    Row({ space: 14 }) {
      // 左侧图源光感图标
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(sourceGlyph(this.presentation().iconToken))
          .fontSize(22)
          .fontColor([!this.source.enabled ? TEXT_SUB : (this.presentation().useAccent ? ACCENT : PRIMARY)])
      }
      .width(46)
      .height(46)
      .borderRadius(14)
      .backgroundColor(!this.source.enabled ? SUB_CARD : (this.presentation().useAccent ? ACCENT_SOFT : PRIMARY_SOFT))

      // 中间名称与精简状态
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(this.source.name)
            .fontColor(this.source.enabled ? TEXT_MAIN : TEXT_SUB)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Circle({ width: 6, height: 6 })
            .fill(this.source.enabled ? STATUS_OK : DIVIDER)
        }
        Text(this.source.kind === 'suwayomi' ? (this.source.endpoint || '点击连接服务')
          : (this.source.enabled ? '点击进入广场浏览' : '已停用'))
          .fontColor(TEXT_SUB)
          .fontSize(12)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 本地漫画专属快捷导入按钮
      if (this.source.kind === 'local' && this.source.enabled) {
        Text('导入')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(PRIMARY)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(PRIMARY_SOFT)
          .onClick(() => {
            this.importLocal();
          })
      }

      // 配置齿轮按钮（收敛节点设置、账号登录、屏蔽规则）
      IconCircleButton({
        glyph: $r('sys.symbol.gearshape'),
        btnSize: 36,
        iconSize: 20,
        bg: SUB_CARD,
        onTap: (): void => {
          this.openSourceConfig();
        }
      })

      // 启停开关
      Toggle({ type: ToggleType.Switch, isOn: this.source.enabled })
        .selectedColor(PRIMARY)
        .systemMaterial(IMMERSIVE_REGULAR_MATERIAL)
        .onChange((enabled: boolean) => {
          const updated: SourceEntry = copySource(this.source);
          updated.enabled = enabled;
          sourceStore.save(updated).catch((e: Error) => {
            this.reportError(errorMessage(e));
            this.reloadSources();
          });
        })
    }
    .padding({ left: 16, right: 14, top: 14, bottom: 14 })
    .width('100%')
    .backgroundColor(CARD)
    .borderRadius(18)
    .border({ width: 0.5, color: DIVIDER })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      this.onPrimaryBrowse();
    })
  }
}
