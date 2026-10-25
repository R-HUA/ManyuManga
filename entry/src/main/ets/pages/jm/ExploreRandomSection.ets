import { SectionErrorRow } from './SectionErrorRow';
import { badgeForAlbum as badgeFor } from '../../common/ComicBadge';
import { RandomCardCell } from './RandomCardCell';
import { CURRENT_BREAKPOINT_KEY } from '../../entryability/EntryAbility';
import { PRIMARY, TEXT_MAIN, TEXT_SUB, CHIP_BG, CHIP_R, FONT_TITLE, FONT_CAPTION, SPACE_S, SPACE_M, SPACE_L } from '../../common/Theme';
import { ComicCard } from '../../common/Components';
import { AlbumLite } from '../../models/Models';

@Component
export struct ExploreRandomSection {
  @Link randomLoading: boolean;
  onShuffleTap: () => void = (): void => {};
  @Link randomItems: Array<AlbumLite>;
  @Link randomError: string;
  retryRandom: () => void = (): void => {};
  openAlbum: (aid: string) => void = (aid: string): void => {};
  @Link randomSeed: number;
  private fillerIndexes(count: number): Array<number> {
    const list: Array<number> = [];
    for (let i: number = 0; i < count; i++) {
      list.push(i);
    }
    return list;
  }
  @StorageProp(CURRENT_BREAKPOINT_KEY) bp: string = 'sm';

  build() {
    Column({ space: SPACE_M }) {
      Row() {
        Text('随机推荐')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)
        Row({ space: SPACE_S }) {
          Text(this.randomLoading ? '刷新中…' : '换一批')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(PRIMARY)
        }
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .backgroundColor(CHIP_BG)
        .borderRadius(CHIP_R)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onShuffleTap();
        })
      }
      .width('100%')
      .padding({ left: SPACE_L, right: SPACE_M })

      if (this.randomLoading && this.randomItems.length === 0) {
        this.RandomSkeleton()
      } else if (this.randomError !== '' && this.randomItems.length === 0) {
        SectionErrorRow(this.randomError, (): void => {
          this.retryRandom();
        })
      } else if (this.randomItems.length === 0) {
        Text('点击「换一批」看看有什么新发现')
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
          .padding({ left: SPACE_L })
      } else {
        this.RandomGrid()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RandomGrid() {
    Column({ space: SPACE_M }) {
      ForEach(this.chunkRows(this.randomItems, this.gridColumns()), (row: Array<AlbumLite>, rIdx: number) => {
        Row({ space: SPACE_L }) {
          ForEach(row, (it: AlbumLite, cIdx: number) => {
            Column() {
              RandomCardCell({
                aid: it.id,
                coverUrl: it.coverUrl,
                title: it.title,
                author: it.author,
                badge: badgeFor(it),
                delayMs: (rIdx * this.gridColumns() + cIdx) * 70,
                onOpen: (aid: string): void => {
                  this.openAlbum(aid);
                }
              })
            }
            .layoutWeight(1)
          }, (it: AlbumLite) => `rand_${this.randomSeed}_${it.id}`)
          ForEach(this.fillerIndexes(this.gridColumns() - row.length), (k: number) => {
            Column()
              .layoutWeight(1)
          }, (k: number) => `rf_${this.randomSeed}_${k}`)
        }
        .width('100%')
        .padding({ left: SPACE_L, right: SPACE_L })
      }, (row: Array<AlbumLite>) => `randrow_${this.randomSeed}_${row[0].id}`)
    }
    .width('100%')
  }

  @Builder
  RandomSkeleton() {
    Column({ space: SPACE_M }) {
      ForEach(this.fillerIndexes(2), (r: number) => {
        Row({ space: SPACE_L }) {
          ForEach(this.fillerIndexes(this.gridColumns()), (c: number) => {
            Column() {
              ComicCard({ loading: true })
            }
            .layoutWeight(1)
          }, (c: number) => `rnsk_${r}_${c}`)
        }
        .width('100%')
        .padding({ left: SPACE_L, right: SPACE_L })
      }, (r: number) => 'rnsk_row_' + r.toString())
    }
    .width('100%')
  }

  private gridColumns(): number {
    return this.bp === 'sm' ? 3 : (this.bp === 'md' ? 4 : 5);
  }

  private chunkRows(items: Array<AlbumLite>, size: number): Array<Array<AlbumLite>> {
    const rows: Array<Array<AlbumLite>> = [];
    for (let i: number = 0; i < items.length; i += size) {
      rows.push(items.slice(i, i + size));
    }
    return rows;
  }
}
