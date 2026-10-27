import { ReaderMode } from '../../models/Models';
import { PRIMARY } from '../../common/Theme';

class ModeItem {
  mode: ReaderMode;
  label: string;
  icon: Resource;

  constructor(mode: ReaderMode, label: string, icon: Resource) {
    this.mode = mode;
    this.label = label;
    this.icon = icon;
  }
}

const PANEL_BG: string = 'rgba(28,28,32,0.86)';

@Component
export struct ReaderModePanel {
  @Link mode: ReaderMode;
  switchMode: (m: ReaderMode) => void = (m: ReaderMode): void => {};

  private readonly modeList: ModeItem[] = [
    new ModeItem('vertical', '纵向条漫', $r('sys.symbol.doc_plaintext')),
    new ModeItem('pagedVertical', '纵向翻页', $r('sys.symbol.page_turning')),
    new ModeItem('horizontal', '左右翻页', $r('sys.symbol.rectangle_on_rectangle')),
    new ModeItem('rtl', '日漫右翻', $r('sys.symbol.book_pages')),
    new ModeItem('double', '双页拼合', $r('sys.symbol.rectangle_split_2x1'))
  ];

  build() {
    Row({ space: 6 }) {
      ForEach(this.modeList, (item: ModeItem) => {
        Column({ space: 4 }) {
          SymbolGlyph(item.icon)
            .fontSize(22)
            .fontColor([this.mode === item.mode ? Color.White : 'rgba(255,255,255,0.82)'])
          Text(item.label)
            .fontSize(11)
            .fontWeight(this.mode === item.mode ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(this.mode === item.mode ? Color.White : 'rgba(255,255,255,0.72)')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height(60)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .borderRadius(14)
        .backgroundColor(this.mode === item.mode ? PRIMARY : 'rgba(255,255,255,0.06)')
        .border({
          width: 0.5,
          color: this.mode === item.mode ? PRIMARY : 'rgba(255,255,255,0.10)'
        })
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
        .onClick(() => {
          this.switchMode(item.mode);
        })
      }, (item: ModeItem): string => item.mode)
    }
    .width('100%')
    .padding(6)
    .borderRadius(18)
    .backgroundColor(PANEL_BG)
    .border({ width: 0.5, color: 'rgba(255,255,255,0.12)' })
  }
}
