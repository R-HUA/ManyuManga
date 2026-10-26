import { IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { SourceEntry, copySource, sourceStore } from '../../data/Sources';
import { sourceApi } from '../../data/SourceApi';
import { SourceCapabilities, capabilitiesFor } from '../../data/source/SourceContracts';
import {
  SourceAction,
  SourcePresentation,
  presentationFor,
  sourceActions,
  sourceSubtitle
} from '../../data/source/SourceCatalog';
import { sourceGlyph } from '../../common/SourceGlyph';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_BLOCK_RULES, ROUTE_SEARCH } from '../../common/Route';
import { errorMessage } from '../../models/Models';
import {
  CARD, SUB_CARD, PRIMARY, PRIMARY_SOFT, ACCENT, ACCENT_SOFT, DANGER, DANGER_SOFT,
  STATUS_OK, TEXT_MAIN, TEXT_SUB, DIVIDER
} from '../../common/Theme';

@Component
export struct SourceEntryCard {
  @Consume('navPathStack') stack: NavPathStack;
  @Prop source: SourceEntry = new SourceEntry();
  @Prop busy: boolean = false;
  @State directText: string = '';
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

  private isActionEnabled(action: SourceAction): boolean {
    if (action.requiresEnabled && (!this.source.enabled || this.busy)) {
      return false;
    }
    return true;
  }

  private run(action: SourceAction): void {
    if (!this.isActionEnabled(action)) {
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

  private jump(): void {
    if (!this.source.enabled) {
      return;
    }
    try {
      const aid: string = sourceApi.resolveDirectKey(this.source, this.directText);
      this.stack.pushPathByName(ROUTE_ALBUM, { aid: aid } as MangaRouteParams);
    } catch (e) {
      this.reportError(errorMessage(e as Error));
    }
  }

  @Builder
  private ActionPill(action: SourceAction) {
    Text(action.label)
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(!this.isActionEnabled(action) ? TEXT_SUB : (action.primary ? PRIMARY : (action.danger ? DANGER : TEXT_MAIN)))
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 9, bottom: 9 })
      .borderRadius(16)
      .backgroundColor(action.primary ? PRIMARY_SOFT : (action.danger ? DANGER_SOFT : SUB_CARD))
      .border({ width: 0.5, color: action.primary ? PRIMARY : DIVIDER })
      .opacity(this.isActionEnabled(action) ? 1.0 : 0.45)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
      .onClick((): void => {
        this.run(action);
      })
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(sourceGlyph(this.presentation().iconToken))
            .fontSize(22)
            .fontColor([this.presentation().useAccent ? ACCENT : PRIMARY])
        }
        .width(44)
        .height(44)
        .borderRadius(14)
        .backgroundColor(this.presentation().useAccent ? ACCENT_SOFT : PRIMARY_SOFT)

        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text(this.source.name)
              .fontColor(TEXT_MAIN)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Circle({ width: 6, height: 6 })
              .fill(this.source.enabled ? STATUS_OK : TEXT_SUB)
          }
          Text(sourceSubtitle(this.source))
            .fontColor(TEXT_SUB)
            .fontSize(12)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

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
      .width('100%')

      if (this.caps().idJump) {
        Row({ space: 8 }) {
          TextInput({ text: this.directText, placeholder: this.presentation().idJumpPlaceholder })
            .layoutWeight(1)
            .height(38)
            .borderRadius(14)
            .backgroundColor(SUB_CARD)
            .fontColor(TEXT_MAIN)
            .placeholderColor(TEXT_SUB)
            .type(this.caps().idJumpNumeric ? InputType.Number : InputType.Normal)
            .onChange((value: string) => {
              this.directText = value;
            })
          Text(this.presentation().idJumpLabel)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.source.enabled ? PRIMARY : TEXT_SUB)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(14)
            .backgroundColor(PRIMARY_SOFT)
            .onClick((): void => {
              this.jump();
            })
        }
        .width('100%')
      }

      Row({ space: 10 }) {
        ForEach(sourceActions(this.source), (action: SourceAction) => {
          this.ActionPill(action)
        }, (action: SourceAction) => `${this.source.id}_${action.label}`)
      }
      .width('100%')

    }
    .padding(16)
    .width('100%')
    .backgroundColor(CARD)
    .borderRadius(20)
    .border({ width: 0.5, color: DIVIDER })
  }
}
