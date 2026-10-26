import promptAction from '@ohos.promptAction';
import { library, LibraryWork } from '../data/Library';
import { MangaRouteParams, ROUTE_ALBUM, ROUTE_READER, ROUTE_DOWNLOADS } from '../common/Route';
import { sourceApi } from '../data/SourceApi';
import { sourceId } from '../data/Sources';
import { capabilitiesForSourceId } from '../data/source/SourceContracts';
import { presentationFor } from '../data/source/SourceCatalog';
import { readProgressStore, historyStore } from '../data/Stores';
import { ReadingProgress, HistoryItem, Album, errorMessage } from '../models/Models';
import { SourceCover } from '../common/SourceCover';
import { IconCircleButton } from '../common/Components';
import {
  BG,
  CARD,
  SUB_CARD,
  TEXT_MAIN,
  TEXT_SUB,
  PRIMARY,
  PRIMARY_SOFT,
  DANGER,
  DIVIDER,
  TAB_BAR_HEIGHT
} from '../common/Theme';
import { TOP_RECT_HEIGHT_KEY, BOTTOM_RECT_HEIGHT_KEY } from '../entryability/EntryAbility';

@Component
export struct UpdatesPage {
  @Consume('navPathStack') stack: NavPathStack;
  @StorageProp(TOP_RECT_HEIGHT_KEY) topInset: number = 0;
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  @StorageProp('currentBreakpoint') breakpoint: string = 'sm';
  @StorageProp('mainTabIndex') @Watch('tabChanged') tab: number = 0;
  @StorageProp('bookshelfDataVersion') @Watch('load') version: number = 0;

  @State works: Array<LibraryWork> = [];
  @State recent: Array<ReadingProgress> = [];
  @State history: Array<HistoryItem> = [];
  @State errors: Array<string> = [];
  @State busy: boolean = false;
  @State section: number = 0;

  private generation: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.generation++;
  }

  private tabChanged(): void {
    if (this.tab === 1) {
      this.refresh();
    } else {
      this.generation++;
      this.busy = false;
    }
  }

  private async load(): Promise<void> {
    try {
      this.works = await library.list();
      this.recent = await readProgressStore.list();
      this.history = await historyStore.getList();
    } catch (e) {
      this.errors = [errorMessage(e as Error)];
    }
  }

  private async refresh(): Promise<void> {
    if (this.busy) {
      return;
    }
    const ticket: number = ++this.generation;
    this.busy = true;
    this.errors = [];
    try {
      const works: Array<LibraryWork> = await library.list();
      let cursor: number = 0;
      const worker = async (): Promise<void> => {
        while (cursor < works.length && ticket === this.generation) {
          const work: LibraryWork = works[cursor++];
          try {
            const album: Album = await sourceApi.album(work.activeKey, true);
            if (ticket !== this.generation) {
              return;
            }
            await library.updateSnapshot(album);
          } catch (e) {
            if (ticket === this.generation) {
              this.errors = this.errors.concat([`${work.title}：${errorMessage(e as Error)}`]);
            }
          }
        }
      };
      await Promise.all([worker(), worker(), worker()]);
      if (ticket === this.generation) {
        await this.load();
      }
    } catch (e) {
      if (ticket === this.generation) {
        this.errors = [errorMessage(e as Error)];
      }
    } finally {
      if (ticket === this.generation) {
        this.busy = false;
      }
    }
  }

  private updatedWorks(): Array<LibraryWork> {
    return this.works.filter((w: LibraryWork) => w.newChapters > 0);
  }

  private safeSourceBadge(key: string): string {
    try {
      return presentationFor(capabilitiesForSourceId(sourceId(key)).kind).shortLabel;
    } catch (e) {
      return '';
    }
  }

  @Builder
  private SegmentPill(label: string, count: number, idx: number) {
    Row({ space: 6 }) {
      Text(label)
        .fontSize(13)
        .fontWeight(this.section === idx ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.section === idx ? Color.White : TEXT_SUB)
      if (count > 0) {
        Text(`${count}`)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.section === idx ? PRIMARY : TEXT_SUB)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .backgroundColor(this.section === idx ? Color.White : SUB_CARD)
      }
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .height(36)
    .borderRadius(18)
    .backgroundColor(this.section === idx ? PRIMARY : 'transparent')
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => {
      this.section = idx;
    })
  }

  @Builder
  private Entry(title: string, cover: string, subtitle: string, badge: string, key: string, reading: boolean) {
    Row({ space: 14 }) {
      Column() {
        SourceCover({ url: cover, sourceKey: key, radius: 10 })
      }
      .width(56)
      .height(74)

      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text(this.safeSourceBadge(key))
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(PRIMARY)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
            .backgroundColor(PRIMARY_SOFT)
          Text(title)
            .fontColor(TEXT_MAIN)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        Text(subtitle)
          .fontColor(TEXT_SUB)
          .fontSize(12)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(badge)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(reading ? Color.White : PRIMARY)
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
        .borderRadius(16)
        .backgroundColor(reading ? PRIMARY : PRIMARY_SOFT)
    }
    .padding(12)
    .width('100%')
    .backgroundColor(CARD)
    .borderRadius(18)
    .border({ width: 0.5, color: DIVIDER })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      this.stack.pushPathByName(reading ? ROUTE_READER : ROUTE_ALBUM, { aid: key } as MangaRouteParams);
    })
  }

  @Builder
  private EmptySection(title: string, desc: string, actionLabel: string, onTap: () => void) {
    Column({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(28)
          .fontColor([PRIMARY])
      }
      .width(60)
      .height(60)
      .borderRadius(30)
      .backgroundColor(PRIMARY_SOFT)

      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
      Text(desc)
        .fontSize(12)
        .fontColor(TEXT_SUB)
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })

      if (actionLabel !== '') {
        Text(actionLabel)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .borderRadius(18)
          .backgroundColor(PRIMARY)
          .onClick(() => {
            onTap();
          })
      }
    }
    .padding({ top: 64, bottom: 48 })
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column({ space: 12 }) {
      // Top Header
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('动态')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_MAIN)
          if (this.busy) {
            Text('正在检查书架更新…')
              .fontSize(11)
              .fontColor(PRIMARY)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.section === 2 && this.history.length > 0) {
          IconCircleButton({
            glyph: $r('sys.symbol.trash'),
            onTap: (): void => {
              this.getUIContext().showAlertDialog({
                title: '清空浏览历史',
                message: '确定清空所有浏览历史记录吗？书架与阅读进度不受影响。',
                primaryButton: { value: '取消', action: () => {} },
                secondaryButton: {
                  value: '清空',
                  fontColor: DANGER,
                  action: () => {
                    historyStore.clear().then(() => {
                      this.load();
                      promptAction.showToast({ message: '已清空浏览历史' });
                    });
                  }
                }
              });
            }
          })
        }

        IconCircleButton({
          glyph: $r('sys.symbol.arrow_clockwise'),
          active: this.busy,
          onTap: (): void => {
            this.refresh();
          }
        })

        IconCircleButton({
          glyph: $r('sys.symbol.arrow_down_circle'),
          onTap: (): void => {
            this.stack.pushPathByName(ROUTE_DOWNLOADS, {} as MangaRouteParams);
          }
        })
      }
      .padding({ left: 16, right: 16, top: this.topInset + 10, bottom: 4 })
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 3-Segment Switcher
      Row({ space: 4 }) {
        this.SegmentPill('更新', this.updatedWorks().length, 0)
        this.SegmentPill('最近阅读', this.recent.length, 1)
        this.SegmentPill('浏览历史', this.history.length, 2)
      }
      .padding(3)
      .margin({ left: 16, right: 16 })
      .borderRadius(19)
      .backgroundColor(SUB_CARD)
      .border({ width: 0.5, color: DIVIDER })

      Scroll() {
        Column({ space: 10 }) {
          if (this.errors.length > 0) {
            Column({ space: 4 }) {
              ForEach(this.errors, (err: string) => {
                Text(err)
                  .fontSize(11)
                  .fontColor(TEXT_SUB)
                  .width('100%')
              }, (err: string) => err)
            }
            .padding(12)
            .borderRadius(14)
            .backgroundColor(CARD)
            .width('100%')
          }

          if (this.section === 0) {
            ForEach(this.updatedWorks(), (w: LibraryWork) => {
              this.Entry(w.title, w.cover, `发现 ${w.newChapters} 个新章节`, `+${w.newChapters} 话`, w.activeKey, false)
            }, (w: LibraryWork) => `${w.id}_${w.newChapters}`)

            if (this.updatedWorks().length === 0) {
              this.EmptySection(
                '暂无新章节提醒',
                '书架作品均为最新状态',
                this.busy ? '检查中…' : '检查更新',
                () => {
                  this.refresh();
                }
              )
            }
          } else if (this.section === 1) {
            ForEach(this.recent, (p: ReadingProgress) => {
              this.Entry(
                p.title,
                p.coverUrl,
                `${new Date(p.at).toLocaleDateString()} 读至第 ${p.page + 1} / ${Math.max(1, p.totalPages)} 页`,
                '继续读',
                p.aid,
                true
              )
            }, (p: ReadingProgress) => `${p.aid}_${p.at}`)

            if (this.recent.length === 0) {
              this.EmptySection(
                '还没有阅读进度',
                '翻阅任意漫画章节后，系统会自动记录精确到页码的阅读位置',
                '去书架看看',
                () => {
                  AppStorage.setOrCreate('mainTabIndex', 0);
                }
              )
            }
          } else {
            ForEach(this.history, (h: HistoryItem) => {
              this.Entry(
                h.title,
                h.coverUrl,
                `浏览于 ${new Date(h.viewedAt).toLocaleDateString()}${h.author ? '  ' + h.author : ''}`,
                '查看',
                h.id,
                false
              )
            }, (h: HistoryItem) => `${h.id}_${h.viewedAt}`)

            if (this.history.length === 0) {
              this.EmptySection(
                '暂无浏览历史',
                '浏览过的作品会自动留存在这里，方便随时找回',
                '',
                () => {}
              )
            }
          }
        }
        .padding({
          left: 16,
          right: 16,
          bottom: (this.breakpoint === 'lg' ? 28 : TAB_BAR_HEIGHT + 28) + this.bottomInset
        })
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG)
  }
}
