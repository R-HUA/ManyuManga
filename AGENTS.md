# AGENTS.md — ManyuManga UI 开发规则

本仓库是 HarmonyOS ArkTS 应用（HDS：HdsNavigation / HdsNavDestination / HdsTabs）。写 UI 前请先读完本文件。
官方文档位于 `https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/<页面>`（下文记作 `UX/`）。旧的 `/doc/design-guides/` 已经失效。这些页面依赖 JS 渲染，WebFetch 常常抓不到正文，请用浏览器阅读。

## 0. 规则的来源、范围和优先级
| 类别 | 来源 | 作用范围 | 优先级 |
|---|---|---|---|
| 官方硬性规定 | HarmonyOS Design 官方原文（见 §1） | 所有 UI | 最高，不得违反 |
| 项目约定 | 本仓库已落地的做法（§2） | 本仓库 UI | 次之；要偏离必须在交付说明里写明理由 |
| 【建议】 | 官方未明确，经验做法 | 视情况 | 最低，可以讨论 |
| 工程规则 | 本仓库（§3～§5） | 所有改动 | 必须遵守 |

## 1. 官方规范（唯一事实源）
- 官方原文、URL 和核实日期统一维护在 **harmonyos-ui-review skill 的「官方规范表」**（核实日期 2026-10-31）。本文件不再复制那张表；需要数值时去查那张表，并直接引用原文。
- 文档地址：`https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/<页面>`（下文记作 `UX/`）。页面依赖 JS 渲染，请用浏览器阅读。
- 本仓库常驻的硬规定只保留以下几条：
  - 底部页签和工具栏不能同时使用；工具栏最多 4 个操作 + 1 个更多，不能只剩"更多"，也不能只有 1 个操作（UX/toolbar-0000001929683232）。
  - 按钮重要程度原文为"强调按钮>填充按钮>文字按钮"（页面小标题为 强调/普通/文字，对应 ButtonStyleMode.EMPHASIZED/NORMAL/TEXTUAL）；不可逆操作用红色警告色（UX/button-0000001929683228）。
  - 用语义 Token，并支持深色模式（UX/color-0000001776857164）。
  - 底部控件、弹出框、半模态都要避让导航条（UX/ux-guidelines-general-0000001760708152）。
- 官方未明确：圆角数值、字阶表、空状态规范、"每屏只能有一个强调按钮"、键盘避让的具体做法。

## 2. 项目约定（来源：本仓库；范围：本仓库 UI；优先级低于 §1）
- **设置和操作类内容放到独立的二级页面**（HdsNavDestination），不放进 bindSheet。Sheet 只用于轻量筛选或选择。
- **多选**统一使用 `common/SelectionToolBar.ets`（`ToolAction` + `buildToolBar` + `SelectionToolBar`）：
  - 工具栏放 4 个操作，加一个"更多"（用 `showActionMenu`）；危险操作 `danger=true`，显示红色。
  - 标题显示"已选 N 项"，标题栏菜单提供"退出选择"（xmark）。
  - 多选时隐藏底部 Tab（MainShell 里的 `barHeight(... || this.selecting ? 0 : -1)`）。
  - 每张卡片都显示勾选圈，未选中的用 OVERLAY_SCRIM 底。
  - 不可用的操作设为 DISABLE，或者干脆不放进工具栏。
- **分段切换用 `SegmentButton`**，不要用手写胶囊 Tab。
- **按钮**用 `Button(label, { buttonStyle: ButtonStyleMode.EMPHASIZED | NORMAL | TEXTUAL, controlSize })`。不要用 Text + backgroundColor(PRIMARY) 手写按钮。每个页面或 Sheet 默认只放一个 EMPHASIZED 按钮（项目约定，官方未规定）。
- **空状态**统一用 `common/Components.ets` 的 `EmptyView`（有 quiet、message、showRetry 参数）。"到底了"提示用 `sys.color.font_tertiary`，居中显示。
- **颜色**只从 `common/Theme.ets` 取（PRIMARY、ON_PRIMARY、OVERLAY_SCRIM、ON_OVERLAY、WARNING、DANGER、TEXT_*、SUB_CARD、BG…），或者直接用 `$r('sys.color.*')`。不要写 `Color.White`、`'#…'`、`'rgba(…)'`。新增颜色要同时写进 base 和 dark 两份 color.json。
- **材质**（systemMaterial）只用在标题栏、Tabs、Sheet，以及 Toggle、Slider、Select 等控件上。内容卡片和浮动栏用 `sys.color.comp_background_list_card` 加 `ShadowStyle.OUTER_DEFAULT_SM`。
- 可滚动的主内容要 `.bindToScrollable([scroller])` 到 HdsNavDestination 或 HdsNavigation。
- 页面左右边距 16vp，元素间距 12vp。底部留白要加 `bottomInset`（`@StorageProp(BOTTOM_RECT_HEIGHT_KEY)`），并且至少避让导航条约 28vp（项目约定，官方未给数值）。
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

## 4.1 完成的定义（每次 UI 改动的交付说明都要逐项回答）
1. check-core 的结果，贴出通过数和失败数。
2. 改动清单：文件:行，以及每处改动对应的规则（§1 官方 / §2 约定 / 【建议】）。
3. 没有经过编译验证的 API、sys.symbol、资源名，逐条列为"待 DevEco 验证"，带上文件:行。
4. 交付状态只能三选一：
   - **已验证**：check-core 通过，并且已在 DevEco 中编译，或用真机、预览确认过。
   - **已修改但未编译**：check-core 通过，但没有编译或预览证据。
   - **未完成**：写明哪里没做、缺少什么证据、原因是什么。
5. 没有编译证据时，不得写"已修复"或"已完成"。报告必须单独列出"未完成的内容"和"缺少的证据"，没有也要写"无"。

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
