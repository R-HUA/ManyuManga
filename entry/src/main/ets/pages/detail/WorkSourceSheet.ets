import { MangaRouteParams, ROUTE_SEARCH } from '../../common/Route';
import { Album, errorMessage } from '../../models/Models';
import { sourceId } from '../../data/Sources';
import { library, LibraryWork } from '../../data/Library';
import { IconCircleButton } from '../../common/Components';
import { SUB_CARD, PRIMARY, PRIMARY_SOFT, DANGER, TEXT_MAIN, TEXT_SUB, CHIP_BG, ON_PRIMARY } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

@Component
export struct WorkSourceSheet {
  @Link work: LibraryWork | null;
  @Prop aid: string = '';
  @Link busy: boolean;
  chooseSource: (target: Album) => Promise<void> = async (target: Album): Promise<void> => {};
  refresh: () => Promise<void> = async (): Promise<void> => {};
  @Link error: string;
  @Link sourceSheet: boolean;
  @Consume('navPathStack') stack: NavPathStack;
  add: () => Promise<void> = async (): Promise<void> => {};
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Row() {
          Column({ space: 4 }) {
            Text('多源聚合与无缝换源')
              .fontColor(TEXT_MAIN)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
            Text('切换图源时将自动比对章节并按比例继承阅读页码')
              .fontColor(TEXT_SUB)
              .fontSize(12)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')

        if (this.work !== null) {
          ForEach(this.work.albums, (item: Album) => {
            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  Text(sourceId(item.id).toUpperCase())
                    .fontSize(10)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PRIMARY)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(6)
                    .backgroundColor(PRIMARY_SOFT)
                  Text(item.name)
                    .fontColor(TEXT_MAIN)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')

                Text(`${item.episodes.length} 个章节 (ID: ${item.id})`)
                  .fontColor(TEXT_SUB)
                  .fontSize(11)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              if (item.id === this.aid) {
                SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([PRIMARY])
                  .accessibilityText('当前源')
              } else {
                Button('切换', { buttonStyle: ButtonStyleMode.NORMAL, controlSize: ControlSize.SMALL })
                  .enabled(!this.busy)
                  .onClick(() => {
                  if (item.id !== this.aid && !this.busy) {
                    this.chooseSource(item);
                  }
                })
              }

              if (this.work!.albums.length > 1 && item.id !== this.aid) {
                IconCircleButton({
                  glyph: $r('sys.symbol.trash'),
                  btnSize: 32,
                  iconSize: 15,
                  onTap: (): void => {
                    library.detach(item.id).then(() => {
                      this.refresh();
                    }).catch((e: Error) => {
                      this.error = errorMessage(e);
                    });
                  }
                })
              }
            }
            .padding(14)
            .borderRadius(16)
            .backgroundColor(SUB_CARD)
            .width('100%')
          }, (item: Album) => item.id)

          Button('跨源搜索并关联新图源', { buttonStyle: ButtonStyleMode.EMPHASIZED })
            .width('100%')
            .onClick(() => {
              this.sourceSheet = false;
              this.stack.pushPathByName(ROUTE_SEARCH, { matchAid: this.aid } as MangaRouteParams);
            })
        } else {
          Column({ space: 12 }) {
            Text('当前作品尚未加入书架。加入书架后将自动在所有已启用书源中检索同名作品并聚合备源。')
              .fontSize(13)
              .fontColor(TEXT_SUB)
              .lineHeight(19)
            Row({ space: 12 }) {
              Button('手动跨源搜索', { buttonStyle: ButtonStyleMode.NORMAL })
                .layoutWeight(1)
                .onClick(() => {
                  this.sourceSheet = false;
                  this.stack.pushPathByName(ROUTE_SEARCH, { matchAid: this.aid } as MangaRouteParams);
                })
              Button('加入书架并自动发现', { buttonStyle: ButtonStyleMode.EMPHASIZED })
                .layoutWeight(1)
                .onClick(() => {
                  this.add();
                })
            }
            .width('100%')
          }
          .padding(16)
          .borderRadius(16)
          .backgroundColor(SUB_CARD)
          .width('100%')
        }

        if (this.error !== '') {
          Text(this.error)
            .fontSize(12)
            .fontColor(DANGER)
            .width('100%')
        }
      }
      .padding({ left: 16, right: 16, top: 16, bottom: 28 + this.bottomInset })
      .width('100%')
    }
    .width('100%')
  }
}
