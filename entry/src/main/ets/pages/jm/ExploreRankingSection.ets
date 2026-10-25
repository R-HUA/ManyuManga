import { SectionErrorRow } from './SectionErrorRow';
import { badgeForAlbum as badgeFor } from '../../common/ComicBadge';
import { CARD, TEXT_MAIN, TEXT_SUB, CHIP_BG, MEDAL_GOLD, MEDAL_SILVER, MEDAL_BRONZE, CHIP_R, FONT_TITLE, FONT_CAPTION, SPACE_M, SPACE_L } from '../../common/Theme';
import { ComicCard } from '../../common/Components';
import { AlbumLite, RankingType } from '../../models/Models';

const MEDAL_SILVER_TEXT: string = '#2F3A45';
const RANK_CARD_W: number = 108;
class RankTab {
  order: RankingType;
  label: string;

  constructor(order: RankingType, label: string) {
    this.order = order;
    this.label = label;
  }
}
@Component
export struct ExploreRankingSection {
  @Link rankLoading: boolean;
  @Link rankItems: Array<AlbumLite>;
  @Link rankError: string;
  retryRanking: () => void = (): void => {};
  private rankTabs: Array<RankTab> = [
    new RankTab('mv_t', '日榜'),
    new RankTab('mv_w', '周榜'),
    new RankTab('mv_m', '月榜'),
    new RankTab('mv', '总榜')
  ];
  @Link currentRank: RankingType;
  onRankTabTap: (order: RankingType) => void = (order: RankingType): void => {};
  openAlbum: (aid: string) => void = (aid: string): void => {};
  private fillerIndexes(count: number): Array<number> {
    const list: Array<number> = [];
    for (let i: number = 0; i < count; i++) {
      list.push(i);
    }
    return list;
  }

  build() {
    Column({ space: SPACE_M }) {
      Text('热门榜单')
        .fontSize(FONT_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .padding({ left: SPACE_L })
      this.RankSegments()
      if (this.rankLoading && this.rankItems.length === 0) {
        this.RankSkeleton()
      } else if (this.rankError !== '' && this.rankItems.length === 0) {
        SectionErrorRow(this.rankError, (): void => {
          this.retryRanking();
        })
      } else if (this.rankItems.length === 0) {
        Text('榜单暂无内容')
          .fontSize(FONT_CAPTION)
          .fontColor(TEXT_SUB)
          .padding({ left: SPACE_L })
      } else {
        this.RankCardList()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RankSegments() {
    Row({ space: 2 }) {
      ForEach(this.rankTabs, (tab: RankTab) => {
        Text(tab.label)
          .fontSize(13)
          .fontWeight(this.currentRank === tab.order ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentRank === tab.order ? TEXT_MAIN : TEXT_SUB)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor(this.currentRank === tab.order ? CARD : Color.Transparent)
          .borderRadius(CHIP_R - 3)
          .onClick(() => {
            this.onRankTabTap(tab.order);
          })
      }, (tab: RankTab) => 'seg_' + tab.order)
    }
    .padding(3)
    .backgroundColor(CHIP_BG)
    .borderRadius(CHIP_R)
    .margin({ left: SPACE_L })
  }

  @Builder
  MedalBadge(rank: number) {
    Text(rank.toString())
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(rank === 2 ? MEDAL_SILVER_TEXT : Color.White)
      .textAlign(TextAlign.Center)
      .width(22)
      .height(22)
      .borderRadius(11)
      .backgroundColor(rank === 1 ? MEDAL_GOLD : (rank === 2 ? MEDAL_SILVER : MEDAL_BRONZE))
      .margin(6)
  }

  @Builder
  RankCardList() {
    List({ space: SPACE_M }) {
      ForEach(this.rankItems, (it: AlbumLite, index: number) => {
        ListItem() {
          Stack({ alignContent: Alignment.TopStart }) {
            ComicCard({
              aid: it.id,
              coverUrl: it.coverUrl,
              title: it.title,
              author: it.author,
              badge: badgeFor(it),
              onCardClick: (): void => {
                this.openAlbum(it.id);
              }
            })
            if (index < 3) {
              this.MedalBadge(index + 1)
            }
          }
          .width(RANK_CARD_W)
        }
      }, (it: AlbumLite) => 'rank_' + it.id)
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_L })
    .cachedCount(3)
  }

  @Builder
  RankSkeleton() {
    List({ space: SPACE_M }) {
      ForEach(this.fillerIndexes(4), (i: number) => {
        ListItem() {
          Column() {
            ComicCard({ loading: true })
          }
          .width(RANK_CARD_W)
        }
      }, (i: number) => 'rksk_' + i.toString())
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ left: SPACE_L, right: SPACE_L })
    .cachedCount(2)
  }
}
