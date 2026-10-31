/**
 * entry/src/main/ets/pages/eh/EhFilterSheet.ets
 * 修复截图 4 (202141) 与截图 5 (202150)：
 * 1. 移除与系统右上角 × 冲突的布局，自带紧凑头部与关闭圆钮（配合 bindSheet showClose: false）
 * 2. 搜索模式(4选1)与最低评分(5选1)重构为 34vp 一体式凹槽分段控制器，告别胖椭圆堆叠
 * 3. 10 大画廊分类重构为 5列×2行 等宽色标矩阵 (Grid)，清空/全选改为 26vp 轻量胶囊
 * 4. 砍掉底部冗余的第二排通栏「取消/收起」按钮，单行「重置 + 应用」释放 54vp 空间
 */
import {
  EhSearchFilter,
  EhSearchMode,
  EhCategoryOption,
  EH_CATEGORY_OPTIONS
} from '../../data/eh/EhSearchFilter';
import { IconCircleButton } from '../../common/Components';
import { IMMERSIVE_REGULAR_MATERIAL } from '../../common/ImmersiveMaterials';
import { CARD, SUB_CARD, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB, DIVIDER, ON_PRIMARY } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

class EhFlagRow {
  label: string;
  key: string;

  constructor(label: string, key: string) {
    this.label = label;
    this.key = key;
  }
}

const FLAG_ROWS: Array<EhFlagRow> = [
  new EhFlagRow('搜索画廊标题', 'inName'),
  new EhFlagRow('搜索画廊标签', 'inTags'),
  new EhFlagRow('搜索画廊描述', 'inDescription'),
  new EhFlagRow('搜索种子名称', 'inTorrents'),
  new EhFlagRow('包含低权重标签', 'inLowPowerTags'),
  new EhFlagRow('显示已删除图库', 'showExpunged'),
  new EhFlagRow('显示低评分图库', 'showDownvoted'),
  new EhFlagRow('搜索文件名称', 'inFileName'),
  new EhFlagRow('搜索上传者名称', 'inUploader'),
  new EhFlagRow('搜索种子文件名', 'inTorrentFile')
];

const RATING_OPTIONS: Array<number> = [0, 2, 3, 4, 5];

@Component
export struct EhFilterSheet {
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  /** 是否仅展示画廊分类面板（兼容 categoryOnly 与 searchFilters 两种调用入参） */
  @Prop categoryOnly: boolean = false;
  @Prop searchFilters: boolean = true;
  filter: EhSearchFilter = new EhSearchFilter();
  @State draft: EhSearchFilter = new EhSearchFilter();
  apply: (filter: EhSearchFilter) => void = (): void => {};
  close: () => void = (): void => {};

  aboutToAppear(): void {
    this.draft = new EhSearchFilter();
    this.draft.copyFrom(this.filter);
  }

  private isOnlyCategory(): boolean {
    return this.categoryOnly || !this.searchFilters;
  }

  private flagValue(key: string): boolean {
    switch (key) {
      case 'inName': return this.draft.inName;
      case 'inTags': return this.draft.inTags;
      case 'inDescription': return this.draft.inDescription;
      case 'inTorrents': return this.draft.inTorrents;
      case 'inLowPowerTags': return this.draft.inLowPowerTags;
      case 'showExpunged': return this.draft.showExpunged;
      case 'showDownvoted': return this.draft.showDownvoted;
      case 'inFileName': return this.draft.inFileName;
      case 'inUploader': return this.draft.inUploader;
      case 'inTorrentFile': return this.draft.inTorrentFile;
      default: return false;
    }
  }

  private setFlag(key: string, value: boolean): void {
    switch (key) {
      case 'inName': this.draft.inName = value; break;
      case 'inTags': this.draft.inTags = value; break;
      case 'inDescription': this.draft.inDescription = value; break;
      case 'inTorrents': this.draft.inTorrents = value; break;
      case 'inLowPowerTags': this.draft.inLowPowerTags = value; break;
      case 'showExpunged': this.draft.showExpunged = value; break;
      case 'showDownvoted': this.draft.showDownvoted = value; break;
      case 'inFileName': this.draft.inFileName = value; break;
      case 'inUploader': this.draft.inUploader = value; break;
      case 'inTorrentFile': this.draft.inTorrentFile = value; break;
      default: break;
    }
  }

  private refreshDraft(): void {
    const next: EhSearchFilter = new EhSearchFilter();
    next.copyFrom(this.draft);
    this.draft = next;
  }

  /** 一体式凹槽分段项：搜索模式 */
  @Builder
  private ModeSegmentItem(label: string, mode: EhSearchMode) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.draft.mode === mode ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.draft.mode === mode ? PRIMARY : TEXT_SUB)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(10)
      .backgroundColor(this.draft.mode === mode ? CARD : Color.Transparent)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
      .onClick(() => {
        this.draft.mode = mode;
        this.refreshDraft();
      })
  }

  /** 一体式凹槽分段项：最低评分 */
  @Builder
  private RatingSegmentItem(value: number) {
    Text(value === 0 ? '不限' : `${value}星+`)
      .fontSize(12)
      .fontWeight(this.draft.minRating === value ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.draft.minRating === value ? PRIMARY : TEXT_SUB)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(30)
      .borderRadius(10)
      .backgroundColor(this.draft.minRating === value ? CARD : Color.Transparent)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
      .onClick(() => {
        this.draft.minRating = value;
        this.refreshDraft();
      })
  }

  /** 2×5 等宽画廊分类矩阵单元 */
  @Builder
  private CategoryGridCell(option: EhCategoryOption) {
    Row({ space: 8 }) {
      Circle({ width: 8, height: 8 })
        .fill(option.color)
      Text(option.label)
        .fontSize(13)
        .fontWeight(this.draft.categoryOn(option.bit) ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.draft.categoryOn(option.bit) ? ON_PRIMARY : TEXT_MAIN)
        .maxLines(1)
        .layoutWeight(1)
      if (this.draft.categoryOn(option.bit)) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([ON_PRIMARY])
      }
    }
    .width('100%')
    .height(34)
    .padding({ left: 10, right: 10 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(10)
    .backgroundColor(this.draft.categoryOn(option.bit) ? option.color : SUB_CARD)
    .border({
      width: 0.5,
      color: this.draft.categoryOn(option.bit) ? option.color : DIVIDER
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
    .onClick(() => {
      this.draft.toggleCategory(option.bit);
      this.refreshDraft();
    })
  }

  @Builder
  private FlagRow(row: EhFlagRow) {
    Row() {
      Text(row.label)
        .fontSize(13)
        .fontColor(TEXT_MAIN)
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.flagValue(row.key) })
        .selectedColor(PRIMARY)
        .onChange((on: boolean) => {
          this.setFlag(row.key, on);
          this.refreshDraft();
        })
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column({ space: 14 }) {
      // ── 顶部标题栏（配合 bindSheet showClose: false，彻底消除右上角 × 重叠） ──
      Row({ space: 10 }) {
        Text(this.isOnlyCategory() ? '画廊分类' : '搜索筛选')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .layoutWeight(1)

        IconCircleButton({
          glyph: $r('sys.symbol.xmark'),
          btnSize: 32,
          iconSize: 16,
          onTap: (): void => {
            this.close();
          }
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12 })

      Scroll() {
        Column({ space: 16 }) {
          if (!this.isOnlyCategory()) {
            // ── 1. 搜索模式（一体式凹槽分段器） ──
            Column({ space: 8 }) {
              Text('搜索模式')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_SUB)
              Row({ space: 4 }) {
                this.ModeSegmentItem('普通', 'normal')
                this.ModeSegmentItem('标签', 'tag')
                this.ModeSegmentItem('上传者', 'uploader')
                this.ModeSegmentItem('关注', 'watched')
              }
              .width('100%')
              .padding(3)
              .borderRadius(12)
              .backgroundColor(SUB_CARD)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }

          // ── 2. 画廊分类（5列 × 2行 等宽色标矩阵） ──
          Column({ space: 8 }) {
            Row() {
              Text('画廊分类（点击切换启用/排除）')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_SUB)
                .layoutWeight(1)

              // 紧凑型 26vp 胶囊按钮，杜绝竖向胖椭圆变形
              Button(this.draft.categoryMask === 0x3ff ? '清空全部' : '全选分类',
                { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
                .onClick(() => {
                  this.draft.categoryMask = this.draft.categoryMask === 0x3ff ? 0 : 0x3ff;
                  this.refreshDraft();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Grid() {
              ForEach(EH_CATEGORY_OPTIONS, (option: EhCategoryOption) => {
                GridItem() {
                  this.CategoryGridCell(option)
                }
              }, (option: EhCategoryOption) => `${option.bit}_${this.draft.categoryOn(option.bit)}`)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10)
            .rowsGap(8)
            .width('100%')
            .height(202)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          if (!this.isOnlyCategory()) {
            // ── 3. 最低评分（一体式凹槽分段器） ──
            Column({ space: 8 }) {
              Text('最低评分')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_SUB)
              Row({ space: 4 }) {
                ForEach(RATING_OPTIONS, (value: number) => {
                  this.RatingSegmentItem(value)
                }, (value: number) => `${value}_${this.draft.minRating === value}`)
              }
              .width('100%')
              .padding(3)
              .borderRadius(12)
              .backgroundColor(SUB_CARD)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            // ── 4. 页数区间 ──
            Column({ space: 8 }) {
              Text('页数区间')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(TEXT_SUB)
              Row({ space: 10 }) {
                TextInput({ text: this.draft.pageFrom, placeholder: '最少页数' })
                  .type(InputType.Number)
                  .height(36)
                  .fontSize(13)
                  .layoutWeight(1)
                  .borderRadius(10)
                  .backgroundColor(SUB_CARD)
                  .fontColor(TEXT_MAIN)
                  .placeholderColor(TEXT_SUB)
                  .onChange((s: string) => {
                    this.draft.pageFrom = s;
                  })
                Text('至')
                  .fontSize(12)
                  .fontColor(TEXT_SUB)
                TextInput({ text: this.draft.pageTo, placeholder: '最多页数' })
                  .type(InputType.Number)
                  .height(36)
                  .fontSize(13)
                  .layoutWeight(1)
                  .borderRadius(10)
                  .backgroundColor(SUB_CARD)
                  .fontColor(TEXT_MAIN)
                  .placeholderColor(TEXT_SUB)
                  .onChange((s: string) => {
                    this.draft.pageTo = s;
                  })
                Text('页')
                  .fontSize(12)
                  .fontColor(TEXT_SUB)
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            Divider().color(DIVIDER).width('100%')

            // ── 5. 高级搜索条件折叠区 ──
            Column({ space: 4 }) {
              Row() {
                Column({ space: 2 }) {
                  Text('高级搜索条件 (AdvSearch)')
                    .fontSize(13)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(TEXT_MAIN)
                  Text('细化检索范围、已删除图库与低评分内容')
                    .fontSize(11)
                    .fontColor(TEXT_SUB)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.draft.advanced })
                  .selectedColor(PRIMARY)
                  .onChange((on: boolean) => {
                    this.draft.advanced = on;
                    this.refreshDraft();
                  })
              }
              .width('100%')

              if (this.draft.advanced) {
                Column() {
                  ForEach(FLAG_ROWS, (row: EhFlagRow) => {
                    this.FlagRow(row)
                  }, (row: EhFlagRow) => `${row.key}_${this.flagValue(row.key)}`)
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .margin({ top: 6 })
                .borderRadius(12)
                .backgroundColor(SUB_CARD)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 8 })
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: this.isOnlyCategory() ? 260 : 500 })
      .width('100%')

      // ── 底部单行操作栏（彻底移除第二排冗余的「取消/收起」巨型按钮） ──
      Row({ space: 12 }) {
        Button('重置', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .backgroundColor(SUB_CARD)
          .layoutWeight(1)
          .height(40)
          .onClick(() => {
            this.draft = new EhSearchFilter();
          })

        Button('应用筛选', { type: ButtonType.Capsule, buttonStyle: ButtonStyleMode.NORMAL })
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(ON_PRIMARY)
          .backgroundColor(PRIMARY)
          .layoutWeight(2)
          .height(40)
          .onClick(() => {
            this.draft.save().catch((): void => {});
            this.apply(this.draft);
            this.close();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 4, bottom: 16 + this.bottomInset })
    }
    .width('100%')
  }
}
