/**
 * entry/src/main/ets/pages/jm/ExploreRankingSection.ets
 * 修复截图 2 (202120)：
 * 将「热门榜单」标题与「日榜/周榜/月榜/总榜」紧凑分段器合并为单行头部（高度 30vp），
 * 消除笨重肥大的下拉框与多余的第二行占位。
 */
import { SectionErrorRow } from './SectionErrorRow';
import { badgeForAlbum as badgeFor } from '../../common/ComicBadge';
import {
  CARD,
  SUB_CARD,
  PRIMARY,
  TEXT_MAIN,
  TEXT_SUB,
  MEDAL_GOLD,
  MEDAL_SILVER,
  MEDAL_BRONZE,
  FONT_TITLE,
  FONT_CAPTION,
  SPACE_M,
  SPACE_L
} from '../../common/Theme';
import { ComicCard } from '../../common/Components';
import { AlbumLite, RankingType } from '../../models/Models';

const MEDAL_SILVER_TEXT: string = '#2F3A45';
const RANK_CARD_W: number = 112;

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
  onRankTabTap: (order: RankingType) => void = (_order: RankingType): void => {};
  openAlbum: (aid: string) => void = (_aid: string): void => {};

  private fillerIndexes(count: number): Array<number> {
    const list: Array<number> = [];
    for (let i: number = 0; i < count; i++) {
      list.push(i);
    }
    return list;
  }

  build() {
    Column({ space: SPACE_M }) {
      // 单行紧凑头部：左侧「热门榜单」标题 + 右侧 30vp 凹槽分段器
      Row({ space: 8 }) {
        Row()
          .width(4)
          .height(16)
          .borderRadius(2)
          .backgroundColor(PRIMARY)

        Text('热门榜单')
          .fontSize(FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)

        this.RankSegments()
      }
      .width('100%')
      .padding({ left: SPACE_L, right: SPACE_L })
      .alignItems(VerticalAlign.Center)

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
          .fontSize(12)
          .fontWeight(this.currentRank === tab.order ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.currentRank === tab.order ? PRIMARY : TEXT_SUB)
          .height(26)
          .padding({ left: 10, right: 10 })
          .backgroundColor(this.currentRank === tab.order ? CARD : Color.Transparent)
          .borderRadius(11)
          .onClick(() => {
            this.onRankTabTap(tab.order);
          })
      }, (tab: RankTab) => 'seg_' + tab.order)
    }
    .padding(2)
    .backgroundColor(SUB_CARD)
    .borderRadius(13)
  }

  @Builder
  MedalBadge(rank: number) {
    Text(rank.toString())
      .fontSize(12)
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
