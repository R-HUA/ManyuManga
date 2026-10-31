# AGENTS.md — ManyuManga UI 开发规则

本仓库是 HarmonyOS ArkTS 应用（HDS：HdsNavigation / HdsNavDestination / HdsTabs）。写 UI 前请先读完本文件。
官方文档位于 `https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/<页面>`（下文记作 `UX/`）。旧的 `/doc/design-guides/` 已经失效。这些页面依赖 JS 渲染，WebFetch 常常抓不到正文，请用浏览器阅读。

## 1. 官方硬性规定（已核实原文）
| 主题 | 规定 | 来源 |
|---|---|---|
| 按钮层级 | 强调 > 普通 > 文字。不可逆操作（删除、重置、停止等）用**红色警告色** | UX/button-0000001929683228 |
| 按钮尺寸 | 单按钮最宽 448vp；双按钮左右排列，**间距 12vp**；3 个及以上纵向排列，间距 12vp；在半模态中左右各留 **16vp** | 同上 |
| 带色按钮 | 不要直接写 backgroundColor（沉浸光感） | 同上 |
| 工具栏 | 最多 **4 个操作 + 1 个更多**；不能只有"更多"，也不能只有 1 个操作；默认高度 **52vp**；**底部页签和工具栏不能同时使用** | UX/toolbar-0000001929683232 |
| 列表 | 效率型行高 48/56/64/72/96vp；内容型 64/72/80/96/120vp；右侧元素与中间内容间隔 **12vp**；系统图标 16 或 24vp；横滑操作不超过 3～4 个 | UX/list-0000001929853910 |
| 文本 | 一个页面内的文本样式**不宜超过 3 种**；1fp = 1vp × 缩放 | UX/text-0000001956975261, UX/design-layout-basics-0000001795579413 |
| 半模态 | Large = 屏高 − 信号栏 − 8；Medium = 60%；横屏最宽 480vp；平板默认 480×560vp | UX/bindsheet-0000001956852753 |
| 多选 | 选中态用勾号 | UX/checkbox-0000001957012561 |
| 标题栏 | 默认高 56vp，强调型 112vp；选择界面有独立的标题栏 | UX/titlebar-0000001929628982 |
| 色彩 | 用语义 Token，深浅色同名不同值；onPrimary 不可直接用在一级背景上；应用需支持深色模式 | UX/color-0000001776857164 |
| 避让 | 底部固定控件、键盘、悬浮按钮、弹出框、半模态都要向上避让导航条 | UX/ux-guidelines-general-0000001760708152 |

官方**没有明确**的内容：圆角数值、字阶表、空状态规范、"每屏只能有一个强调按钮"、键盘避让的具体做法。下面的相关条目都属于项目约定。

## 2. 项目约定 / 建议
- **设置和操作类内容放到独立的二级页面**（HdsNavDestination），不放进 bindSheet。Sheet 只用于轻量筛选或选择。
- **多选**统一使用 `common/SelectionToolBar.ets`（`ToolAction` + `buildToolBar` + `SelectionToolBar`）：
  - 工具栏放 4 个操作，加一个"更多"（用 `showActionMenu`）；危险操作 `danger=true`，显示红色。
  - 标题显示"已选 N 项"，标题栏菜单提供"退出选择"（xmark）。
  - 多选时隐藏底部 Tab（MainShell 里的 `barHeight(... || this.selecting ? 0 : -1)`）。
  - 每张卡片都显示勾选圈，未选中的用 OVERLAY_SCRIM 底。
  - 不可用的操作设为 DISABLE，或者干脆不放进工具栏。
- **分段切换用 `SegmentButton`**，不要用手写胶囊 Tab。
- **按钮**用 `Button(label, { buttonStyle: ButtonStyleMode.EMPHASIZED | NORMAL | TEXTUAL, controlSize })`。不要用 Text + backgroundColor(PRIMARY) 手写按钮。每个页面或 Sheet 建议只放一个 EMPHASIZED 按钮。
- **空状态**统一用 `common/Components.ets` 的 `EmptyView`（有 quiet、message、showRetry 参数）。"到底了"提示用 `sys.color.font_tertiary`，居中显示。
- **颜色**只从 `common/Theme.ets` 取（PRIMARY、ON_PRIMARY、OVERLAY_SCRIM、ON_OVERLAY、WARNING、DANGER、TEXT_*、SUB_CARD、BG…），或者直接用 `$r('sys.color.*')`。不要写 `Color.White`、`'#…'`、`'rgba(…)'`。新增颜色要同时写进 base 和 dark 两份 color.json。
- **材质**（systemMaterial）只用在标题栏、Tabs、Sheet，以及 Toggle、Slider、Select 等控件上。内容卡片和浮动栏用 `sys.color.comp_background_list_card` 加 `ShadowStyle.OUTER_DEFAULT_SM`。
- 可滚动的主内容要 `.bindToScrollable([scroller])` 到 HdsNavDestination 或 HdsNavigation。
- 页面左右边距 16vp，元素间距 12vp。底部留白要加 `bottomInset`（`@StorageProp(BOTTOM_RECT_HEIGHT_KEY)`），并且至少避让导航条约 28vp（项目约定）。
- 轻量提示用 `showToast`；不可逆操作先弹 `AlertDialog` 确认，确认按钮用 DANGER 色。
- 表单类 Sheet 加 `keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_SCROLL`。

## 3. ArkTS 编译坑（已踩过）
- `SegmentButtonOptions.tab({ buttons: [...] as ItemRestriction<SegmentButtonTextItem> })`：必须写这个 `as`。
- `tabIndex` 是保留属性名，不要拿它当自定义变量或属性名。
- `sys.symbol.square_grid_3x3` **不存在**。
- 仓库里已确认存在的 sys.symbol：checkmark、chevron_right / left / down / up、xmark、trash、ellipsis_circle、lock_fill、label、arrow_down_circle、checkmark_square_on_square、folder_fill、arrow_clockwise、eye、clock、magnifyingglass、slider_horizontal_2、book、books_vertical_fill。`square_and_arrow_up` 还未确认。
- 严格 ArkTS 规则：
  - 不能用 any 或 unknown，对象字面量要有显式类型（`as T` 或声明 class / interface）。
  - 不能用解构、索引签名，也不能动态增删属性。
  - 箭头函数要写返回类型；`@Builder` 里只能写 UI 语法。
- ToolBar（V1，来自 `@kit.ArkUI`）：
  - `controller: TabsController` 是必填参数；`toolBarList` 是 `@ObjectLink`，更新时要整体赋值一个新的 `ToolBarOptions`。
  - `toolBarSymbolOptions` 需要 API 13 及以上。
  - 不要和 V2 装饰器混用。

## 4. 测试
```
cd /workspace/mmrepo && npx -y node@22 --experimental-sqlite scripts/check-core.mjs /tmp/tsmod/node_modules/typescript
```
必须全部通过（当前基线 97 项）。`scripts/interface-regressions.mjs` 里有静态断言，例如 DownloadsPage 不能出现 bindSheet、ProfilePage 不能出现 Toggle。改 UI 前先看一遍。盒子上没有 ArkTS 编译器，最终要在 DevEco 中编译和验证。

## 5. Git
- 只用普通的 `git push origin <branch>`。**禁止 force-push，禁止改写历史**（不用 rebase、amend 改已推送的提交，也不用 reset --hard 覆盖远端）。
- 提交信息用中文。

## 6. 反模式
- 一整排手写胶囊按钮（筛选项用 SegmentButton、Chip 或列表）。
- 一个页面或 Sheet 里有多个强调按钮，或者主色按钮到处都是。
- 不可用的操作仍然显示成可点击的样子；工具栏只剩一个操作，或只剩"更多"。
- 底部页签和工具栏同时显示。
- 底部内容没有避让导航条（约 28vp 加 bottomInset）；Sheet 里的表单没有键盘避让。
- 内容卡片、搜索框、普通按钮上加材质。
- 硬编码 `Color.White`、rgba，或随手写字号、圆角（如 10/11/13/15/19/21）。
- 空状态只放一行 Text，"暂无内容"和"没有更多了"用同一种样式。
