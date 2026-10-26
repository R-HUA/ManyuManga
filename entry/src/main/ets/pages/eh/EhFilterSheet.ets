/**
 * E-Hentai 高级搜索筛选面板：搜索模式、10 大分类开关（官方色标）、
 * 最低评分、页数区间与 advsearch 十项开关。编辑在副本上进行，
 * 点「应用」才回写并持久化（EhSearchFilter.save）。
 */
import {
  EhSearchFilter,
  EhSearchMode,
  EhCategoryOption,
  EH_CATEGORY_OPTIONS
} from '../../data/eh/EhSearchFilter';
import { SUB_CARD, PRIMARY, PRIMARY_SOFT, TEXT_MAIN, TEXT_SUB, DIVIDER } from '../../common/Theme';
import { BOTTOM_RECT_HEIGHT_KEY } from '../../entryability/EntryAbility';

/** 高级开关行定义（label / EhSearchFilter 字段名一致的取值回调）。 */
class EhFlagRow {
  label: string;
  key: string;

  constructor(label: string, key: string) {
    this.label = label;
    this.key = key;
  }
}

const FLAG_ROWS: Array<EhFlagRow> = [
  new EhFlagRow('标题', 'inName'),
  new EhFlagRow('标签', 'inTags'),
  new EhFlagRow('描述', 'inDescription'),
  new EhFlagRow('种子', 'inTorrents'),
  new EhFlagRow('低权重标签', 'inLowPowerTags'),
  new EhFlagRow('已删除图库', 'showExpunged'),
  new EhFlagRow('低评分图库', 'showDownvoted'),
  new EhFlagRow('文件名', 'inFileName'),
  new EhFlagRow('上传者', 'inUploader'),
  new EhFlagRow('种子文件', 'inTorrentFile')
];

const RATING_OPTIONS: Array<number> = [0, 2, 3, 4, 5];

@Component
export struct EhFilterSheet {
  @StorageProp(BOTTOM_RECT_HEIGHT_KEY) bottomInset: number = 0;
  /** 当前生效的筛选（构造时传入，编辑不落库）。 */
  filter: EhSearchFilter = new EhSearchFilter();
  /** 编辑副本：点「应用」才由父页回写生效。 */
  @State draft: EhSearchFilter = new EhSearchFilter();
  apply: (filter: EhSearchFilter) => void = (): void => {};
  close: () => void = (): void => {};

  aboutToAppear(): void {
    this.draft = new EhSearchFilter();
    this.draft.copyFrom(this.filter);
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

  @Builder
  private ModeChip(label: string, mode: EhSearchMode) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.draft.mode === mode ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.draft.mode === mode ? Color.White : TEXT_MAIN)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(14)
      .backgroundColor(this.draft.mode === mode ? PRIMARY : SUB_CARD)
      .onClick(() => {
        this.draft.mode = mode;
      })
  }

  @Builder
  private CategoryChip(option: EhCategoryOption) {
    Text(option.label)
      .fontSize(12)
      .fontWeight(this.draft.categoryOn(option.bit) ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.draft.categoryOn(option.bit) ? Color.White : TEXT_SUB)
      .padding({ left: 11, right: 11, top: 7, bottom: 7 })
      .margin(4)
      .borderRadius(14)
      .backgroundColor(this.draft.categoryOn(option.bit) ? option.color : SUB_CARD)
      .border({ width: 0.5, color: this.draft.categoryOn(option.bit) ? option.color : DIVIDER })
      .onClick(() => {
        this.draft.toggleCategory(option.bit);
      })
  }

  @Builder
  private RatingChip(value: number) {
    Text(value === 0 ? '不限' : `${value} 星`)
      .fontSize(12)
      .fontWeight(this.draft.minRating === value ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.draft.minRating === value ? Color.White : TEXT_SUB)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .borderRadius(14)
      .backgroundColor(this.draft.minRating === value ? PRIMARY : SUB_CARD)
      .onClick(() => {
        this.draft.minRating = value;
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
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text('高级搜索筛选')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .width('100%')

        // ── 搜索模式 ──
        Column({ space: 8 }) {
          Text('搜索模式').fontSize(12).fontColor(TEXT_SUB)
          Row({ space: 8 }) {
            this.ModeChip('普通', 'normal')
            this.ModeChip('标签', 'tag')
            this.ModeChip('上传者', 'uploader')
            this.ModeChip('关注', 'watched')
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        // ── 分类 ──
        Column({ space: 8 }) {
          Row() {
            Text('画廊分类').fontSize(12).fontColor(TEXT_SUB).layoutWeight(1)
            Text(this.draft.categoryMask === 0x3ff ? '清空' : '全选')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(PRIMARY)
              .onClick(() => {
                this.draft.categoryMask = this.draft.categoryMask === 0x3ff ? 0 : 0x3ff;
              })
          }
          .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(EH_CATEGORY_OPTIONS, (option: EhCategoryOption) => {
              this.CategoryChip(option)
            }, (option: EhCategoryOption) => `${option.bit}`)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        // ── 最低评分 ──
        Column({ space: 8 }) {
          Text('最低评分').fontSize(12).fontColor(TEXT_SUB)
          Row({ space: 8 }) {
            ForEach(RATING_OPTIONS, (value: number) => {
              this.RatingChip(value)
            }, (value: number) => `${value}`)
          }
          .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        // ── 页数区间 ──
        Column({ space: 8 }) {
          Text('页数区间').fontSize(12).fontColor(TEXT_SUB)
          Row({ space: 10 }) {
            TextInput({ text: this.draft.pageFrom, placeholder: '最少' })
              .type(InputType.Number)
              .height(38)
              .layoutWeight(1)
              .borderRadius(12)
              .backgroundColor(SUB_CARD)
              .fontColor(TEXT_MAIN)
              .placeholderColor(TEXT_SUB)
              .onChange((s: string) => {
                this.draft.pageFrom = s;
              })
            Text('至')
              .fontSize(12)
              .fontColor(TEXT_SUB)
            TextInput({ text: this.draft.pageTo, placeholder: '最多' })
              .type(InputType.Number)
              .height(38)
              .layoutWeight(1)
              .borderRadius(12)
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

        // ── 高级开关 ──
        Column({ space: 4 }) {
          Row() {
            Text('高级搜索条件').fontSize(12).fontColor(TEXT_SUB).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.draft.advanced })
              .selectedColor(PRIMARY)
              .onChange((on: boolean) => {
                this.draft.advanced = on;
              })
          }
          .width('100%')
          .padding({ bottom: 4 })

          if (this.draft.advanced) {
            ForEach(FLAG_ROWS, (row: EhFlagRow) => {
              this.FlagRow(row)
            }, (row: EhFlagRow) => row.key)
            Text('评分与页数条件也在高级模式下生效')
              .fontSize(11)
              .fontColor(TEXT_SUB)
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        // ── 操作 ──
        Row({ space: 10 }) {
          Text('重置')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(TEXT_SUB)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(42)
            .borderRadius(21)
            .backgroundColor(SUB_CARD)
            .onClick(() => {
              this.draft = new EhSearchFilter();
            })
          Text('应用')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(42)
            .borderRadius(21)
            .backgroundColor(PRIMARY)
            .onClick(() => {
              this.draft.save().catch((): void => {});
              this.apply(this.draft);
              this.close();
            })
        }
        .width('100%')
        .margin({ top: 4 })

        Text('收起')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_MAIN)
          .textAlign(TextAlign.Center)
          .width('100%')
          .height(42)
          .borderRadius(21)
          .backgroundColor(SUB_CARD)
          .onClick(() => {
            this.close();
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 28 + this.bottomInset })
    }
    .width('100%')
    .scrollBar(BarState.Off)
  }
}
