import { ReaderMode } from '../../models/Models';
import { PRIMARY, PRIMARY_SOFT } from '../../common/Theme';
import { readerModeLabel } from '../../data/ReaderModeCycle';

/** 各阅读模式的图标：底栏「模式」入口用它区分当前模式。 */
export function readerModeIcon(mode: ReaderMode): Resource {
  switch (mode) {
    case 'pagedVertical': return $r('sys.symbol.page_turning');
    case 'horizontal': return $r('sys.symbol.rectangle_on_rectangle');
    case 'rtl': return $r('sys.symbol.book_pages');
    case 'double': return $r('sys.symbol.rectangle_split_2x1');
    default: return $r('sys.symbol.doc_plaintext');
  }
}

class ModeItem {
  mode: ReaderMode;
  label: string;
  icon: Resource;

  constructor(mode: ReaderMode) {
    this.mode = mode;
    this.label = readerModeLabel(mode);
    this.icon = readerModeIcon(mode);
  }
}

@Component
export struct ReaderModePanel {
  @Link mode: ReaderMode;
  switchMode: (m: ReaderMode) => void = (m: ReaderMode): void => {};

  private readonly modeList: ModeItem[] = [
    new ModeItem('vertical'),
    new ModeItem('pagedVertical'),
    new ModeItem('horizontal'),
    new ModeItem('rtl'),
    new ModeItem('double')
  ];

  build() {
    Row({ space: 6 }) {
      ForEach(this.modeList, (item: ModeItem) => {
        Column({ space: 6 }) {
          SymbolGlyph(item.icon)
            .fontSize(22)
            .fontColor([this.mode === item.mode ? PRIMARY : $r('sys.color.font_primary')])
          Text(item.label)
            .fontSize(12)
            .fontWeight(this.mode === item.mode ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.mode === item.mode ? PRIMARY : $r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height(62)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(8)
        .backgroundColor(this.mode === item.mode ? PRIMARY_SOFT : Color.Transparent)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
        .onClick(() => {
          this.switchMode(item.mode);
        })
      }, (item: ModeItem): string => item.mode)
    }
    .width('100%')
  }
}
