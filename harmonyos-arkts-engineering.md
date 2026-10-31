# HarmonyOS ArkTS 工程规范

链接与版本核实日期 2026-10-31。设计规范审查（按钮层级、工具栏、颜色 Token、空状态等）见 harmonyos-ui-review skill / `harmonyos-ui-review.md`，本文聚焦工程实现。

## 1. 依据、工程和版本

- **中文官方文档优先。** 核对当前版本的中文 API 参考、开发指南、行为变更和官方示例；设计决策同时参考中文设计指南及 UX 体验标准。英文文档、旧示例、离线资料和社区文章只作补充。官方来源之间不一致时，区分版本、设备和适用场景；接口签名以目标 SDK 声明核对，实际行为用最小复现验证，不把差异默默改写成事实。
- **版本可用、设备能力和权限是不同条件。** 查询具体 API 的起始／废弃版本、SystemCapability、设备支持、权限、应用模型以及元服务限制；不能只用 ROM 展示版本、`canIUse` 或“能够编译”推断运行时可用。
- 使用 API 26 配套工具链时，按官方推荐用 `deviceInfo.apiAvailable` 做 API 兼容性保护。版本号以字面量直接写入 `apiAvailable` 参数，不要用变量传参，否则编译期检查失效。旧工具链采用该版本官方支持的保护方式。[兼容性保护][compat]

```ts
// API 26 配套 SDK／编译器下的兼容性保护写法。
import { deviceInfo } from '@kit.BasicServicesKit';

function configureFeature(): void {
  if (deviceInfo.apiAvailable('26.0.0')) {
    // 仅在此分支调用要求 26.0.0 的接口。
  } else {
    // 保留低版本可用的交互或实现。
  }
}
```

## 2. ArkTS 类型、外部数据与模块边界

- 当前 ArkTS `.ets` 规则不支持 `any`、`unknown`。使用明确接口、类、联合类型和可空类型；不要用多次 `as`、`as Object as ...` 或忽略检查来掩盖类型错误。这不意味着项目不得存在按各自规则编译的 TS／JS 或 Native 模块。[ArkTS 规则][types]
- 涉及构造逻辑、方法、受限成员或状态观察时，按规则使用类实例。不要依赖字段同形获得结构类型兼容；优先共享类型契约，必要时使用 `implements`／`extends` 或明确的数据转换。[ArkTS 规则][types]
- 外部 JSON 在网络、文件或桥接边界解析并验证：检查字段类型、必填项、范围、数组元素和可接受的缺省值。**类型断言不等于运行时验证**；解析失败和业务不合法分开处理。公共解析逻辑推荐复用。
- JSON 数据不会因为 `as Model` 自动获得类方法或观察能力。需要 `@ObservedV2` 模型时，先校验数据，再 `new` 实例并赋入属性；不要把反序列化对象冒充可观察实例。[观察模型][observed]
- `catch (error)` 不加 TypeScript 式类型注解；按 API 的错误契约提取错误。当前 ArkTS `throw` 要求 `Error` 或其派生类，不使用无验证的断言把任意值伪装成 `Error`。[ArkTS 规则][types]
- 避免组件、类、函数和成员命名与系统组件、生命周期或继承签名冲突；以语义明确的业务名称降低碰撞风险。需要实例上下文的外部回调优先用箭头包装；有特定接收者约定的接口按其契约实现。
- 按职责、可测试性和可复用边界拆分模块。公共文件、数据源、资源访问和组件复用应服务于实际重复。

## 3. 状态管理与声明式刷新

- **新应用优先状态管理 V2。** 使用 `@ComponentV2`、`@Local`、`@Param`、`@Event`；复杂可观察模型按需使用 `@ObservedV2`／`@Trace`。已有 V1 满足需求时不必立即迁移；跨 V1／V2 数据传递遵循正式迁移指导，不能任意混搭装饰器和对象。[状态管理][state]
- 状态由明确的一方持有。输入通过参数下传，修改通过事件或受支持的双向绑定回传；不要直接改写只读输入来“修复刷新”。派生值与源状态避免重复保存。
- V2 自定义组件的 `!!` 语法从 API 12 起支持；**原生 `Toggle.isOn` 的 `!!` 支持从 API 18 起**，不能把运算符的起始版本当作每个系统参数的起始版本。检查具体组件的绑定能力。[双向绑定][binding]
- `@Builder` 当前有按值、按引用、按回调传参等方式。传统引用传参要求直接传入单个对象字面量；**API 20 起可使用 `UIUtils.makeBinding`、`Binding`／`MutableBinding` 实现多参数刷新和显式写回**。根据状态所有者选用方式。[Builder][builder]
- 异步初始化、保存中、保存成功与失败回退分别建模。尚未加载或正在提交时禁用相关操作；程序同步与用户提交应区分，防止重复保存。失败回退必须回到同一状态源，并覆盖快速重复操作和乱序返回。
- 列表项使用稳定、唯一、带业务身份的键。键稳定不会自动使普通对象深层变更可观察；验证属性修改、对象替换、重排和复用后的 UI。V1 的 `@Observed`／`@ObjectLink` 与 V2 的 `@ObservedV2`／`@Trace` 各有适用边界。[列表刷新][foreach]
- 不把 `makeBuilderParameterProxy` 等编译器内部函数名设为验收门槛。排查编译问题可以检查产物，但公开 API 契约和实际 UI 刷新才是跨版本依据。

以下为绑定机制示例，均需在声明的版本条件下纳入实际工程编译、运行；未包含持久化和完整页面设计。

```ts
// API 18+：原生 Toggle 的 V2 双向绑定。
@Entry
@ComponentV2
struct ToggleExample {
  @Local optionOn: boolean = false;

  build() {
    Column() {
      Toggle({ type: ToggleType.Switch, isOn: this.optionOn!! })
        .accessibilityText('功能开关')
      Text(this.optionOn ? '已开启' : '已关闭')
    }
  }
}
```

```ts
// API 20+：Builder 支持多个响应式参数及明确写回。
import { Binding, MutableBinding, UIUtils } from '@kit.ArkUI';

@Builder
function countPanel(caption: Binding<string>, count: MutableBinding<number>) {
  Column() {
    Text(`${caption.value}：${count.value}`)
    Button('增加')
      .buttonStyle(ButtonStyleMode.NORMAL)
      .onClick(() => { count.value += 1; })
  }
}

@Entry
@ComponentV2
struct BindingExample {
  @Local caption: string = '次数';
  @Local count: number = 0;

  build() {
    Column() {
      countPanel(
        UIUtils.makeBinding<string>(() => this.caption),
        UIUtils.makeBinding<number>(
          () => this.count,
          (value: number) => { this.count = value; }
        )
      )
    }
  }
}
```

## 4. 导航、窗口与安全区

- 推荐采用 HDS ，按 `HdsNavigation`／`HdsNavDestination` 的正式组合及对应参数类型实现。 不支持时采用 `Navigation`／`NavDestination` 和对应路由栈；维护旧路由时按迁移指导评估。[导航迁移][navigation]
- 页面应有清晰的导航所有者。嵌入已有导航壳时避免重复标题栏、返回入口和安全区占位；确需多级导航时明确层级与返回行为。
- **按当前窗口与内容容器布局。** 手机横屏、折叠、分屏、自由窗口和外接显示都可能改变可用尺寸；不要仅按设备名称、物理屏幕宽度或屏幕方向决定布局。[响应式设计][layout]
- 分清系统避让区、导航组件安全区、键盘区域、内容内边距和悬浮层覆盖。先确认父容器是否已经避让，再决定子容器是否补偿；不能仅因窗口全屏就重复累加系统导航条高度。
- `HdsNavDestination` 的安全区扩展使用 5.1.0(18) 起的 `ignoreLayoutSafeArea(types?, edges?)`；按当前标题栏、透明度和覆盖布局配置，不以固定顶部 padding 代替。安全区相关属性以目标 SDK 声明为准，不凭其他组件推测属性名。[HDS 导航][hdsnav]
- `HdsTabs` 悬浮页签（`barFloatingStyle`）的 `barBottomMargin` 使用前核对其参照边（官方页面未明确说明），不要默认等于距屏幕底边的距离。悬浮栏、附加操作栏和列表内容的避让要用同一坐标与占位模型，并确保末项及其操作完整可达。[HDS 页签][hdstabs]
- 修改窗口属性前明确目标是“当前 UI 所属窗口”还是“主窗口”。前者可按 API 12 起的 `UIContext.getWindowName()` 查询并处理无结果；后者优先使用已持有的主窗口或 `WindowStage.getMainWindow()`。`getLastWindow()` 返回当前应用最上层的子窗口，无已显示子窗口时才回退为主窗口。设置隐私模式前核对 `setWindowPrivacyMode` 的权限要求等接口条件；异步修改失败时回退 UI 并提示。[UIContext][uicontext] [WindowStage][windowstage] [窗口][window]

## 5. 布局、列表与测量

- **`layoutWeight` 可以用于 `Row`、`Column`、`Flex` 的子组件。** 它影响主轴空间分配；只有确实需要填充剩余空间的节点才使用。表单和滑块不要因套用权重而被意外拉高。[尺寸属性][size]
- 图片按内容选择比例、裁剪和占位策略。已知比例的卡片应预留稳定尺寸以减少跳动；未知比例或需要完整展示的内容可按元数据自适应。
- 优先让网格／瀑布流布局计算列宽。确需自算时统一内容宽度、左右内边距、列数和间距的测量口径；查清百分比相对哪个父约束，避免跨列溢出。不要把卡片尺寸约束复用于文本标签。
- 小规模静态集合可用 `ForEach`。长列表在能力满足时优先评估 `Repeat`（API 12 起）懒加载与复用：`Repeat` 须位于滚动容器内，懒加载模式仅支持 `List`、`ListItemGroup`、`Grid`、`Swiper`、`WaterFlow`；懒加载模式不支持与状态管理 V1 混用（会渲染异常），推荐 V2。已有 `LazyForEach` 按 `IDataSource` 通知契约维护。[Repeat][repeat]
- `LazyVGridLayout`（API 19 起，部分成员 26.0.0 起）／`LazyVWaterFlowLayout`（26.0.0 起）可用于符合约束的纵向懒加载布局。它们不是传统容器的机械替换；例如 `LazyVWaterFlowLayout` 自身需保持高度自适应，官方不建议设置固定高度、限制高度、`aspectRatio` 或 `layoutWeight`。[懒加载瀑布流布局][lazyflow]
- 加载更多、重试和结束状态通常进入列表滚动流；固定工具栏按独立交互需要设计。普通 `WaterFlow` 布局在 API 18 起支持 `footerContent`，`footer` 仍受支持；二者同时设置时前者生效。使用 `sections` 分组混排时，不支持单独的 `footer`／`footerContent`，应按该模式的限制把页脚组织为末组。[WaterFlow][waterflow]
- 需要顶部起始展示的短内容，显式设置 `Scroll.align(Alignment.TopStart)` 等对齐方式，并配置内容宽度；仅设置内部 Column 对齐不能改变外层 Scroll 默认居中。居中空态等场景可有意保留居中。[Scroll][scroll] [位置设置][position]
- 首帧尽量具有稳定约束。固定规格元素可共享尺寸 token；会随字体、语言和宽度变化的元素使用自适应布局或可靠测量，不强制所有标题／筛选栏固定高度。避免先放一个大占位数再靠 `onAreaChange` 跳变修正。
- 判断折叠内容是否溢出时，测量未裁剪的自然内容或使用适合该布局的测量能力；不要测量已经被固定高度截断的结果。禁滚 Scroll 只是可选实现，不是通用必需容器。折叠行数与恢复规则由任务场景决定。
- 界面按窗口断点、宽高比和文本变化自适应，覆盖深浅色、大字体、长文本、RTL、键鼠焦点及触屏操作；不为所有设备固化同一列数、边距或导航模式。[响应式设计][layout] [全球化][global]

## 6. HDS、沉浸光感与颜色

- 优先使用系统控件及正式设计能力，再根据产品需要定制。 标准 ArkUI 与 HDS 的同名属性、参数类型和起始版本分别核验；API 26 的标准 Tabs 也已提供悬浮页签相关能力。[标准 Tabs][tabs]
- 采用 ArkUI `uiMaterial`／`systemMaterial` 路线时，按开启指南确认 `targetSdkVersion` 不低于 26.0.0，并检查运行设备和接口可用性；HDS `systemMaterialEffect` 从 6.1.0(23) 起支持，按其对应文档单独判断兼容性，不把 API 26 门槛套到全部 HDS 能力。[开启沉浸光感][material] [HDS 材质][hdsmaterial]
- ArkUI 这条路线当前有生效区域限制：指定弹窗及相关接口、Slider／Toggle／Select 可在页面内生效；其他组件仅在 Navigation／NavDestination 标题栏及 `barPosition` 为 `BarPosition.End` 的 Tabs 底部 TabBar 等允许区域生效。以最新组件清单为准，不向任意普通 Column 强挂材质。[开启沉浸光感][material]
- **先核对默认行为，再决定是否显式配置。** 官方说明：从低于 API 26 升级到 26.0.0 及以上且未主动配置时，受支持组件可默认开启。仅 entry 模块的 `metadata` 可统一控制，取值 `default`／`enable`／`disable`（`default` 与 `enable` 均为开启）；组件接口可调整效果，全局 `disable` 则使两种开启方式均失效。[开启沉浸光感][material]
- 明确关闭默认沉浸效果使用 `uiMaterial.Material.empty`。关于 `undefined`，开启指南称其恢复组件默认，而通用属性表另有“恢复无材质”的措辞；按具体组件／接口核对，**不要把 `undefined` 当作统一关闭方法**。Select 按钮与其下拉菜单等子区域可能由不同接口控制。[开启沉浸光感][material] [材质通用属性][materialattr]
- 材质参数、模糊与表面颜色可归集为语义 token。目标是可读性、层次和平台效果；叠加背景色前核验接口覆盖关系及实际效果，避免不透明层意外遮挡采样内容。
- 开启 `colorInvert` 时按当前 `ImmersiveOptions` 支持的属性和系统资源清单选色，不能仅限定 `font_primary`／`font_secondary`，也不能假定任意自定义资源都会自动反色。品牌色、警示色和选中态需要分别检查对比度。[材质 API][uimaterial]
- 非生效区域需要模糊时，按场景评估普通背景模糊、透明底色或不透明表面；它们与沉浸光感并非同一效果。不把某个 `BlurStyle` 强制作为所有悬浮面板的替代；大面积、多层或动态模糊要验证性能与功耗。
- HDS 标题模式、字号、菜单 `content` 类型、搜索及自定义标题槽位按正式声明选择。`stackBuilder` 不是任意位置的标题行插槽；避免靠负偏移、固定左 padding 拼接返回与搜索。标题高度等枚举先查当前 SDK，不凭其他组件推测名字。[HDS 导航][hdsnav]
- HDS 标题栏按钮效果与随滚动变化的背景模糊分别配置；Scroller 关联、分栏／堆叠模式按页面结构和设备确定。`FREE`／`MINI`、默认 56vp 悬浮栏高度等属于具体组件规格，不应上升为所有产品的固定外观，更不要覆写成猜测尺寸。[HDS 导航][hdsnav] [HDS 页签][hdstabs]

需要显式统一开启时，把以下条目合并到现有 **entry 模块** 的 `metadata` 数组，不覆盖其他配置：

```json5
{
  "name": "ohos.arkui.UIMaterial.state",
  "value": "enable"
}
```

## 7. 控件、弹层、可访问性与文案

- 控件按任务语义选择：操作用 Button，开关用 Toggle；少量互斥选项、多个可选标签和大量候选分别评估分段按钮、选择块、Select 或选择面板。不要把所有筛选统一改成某一种控件。
- 按钮层级（`ButtonStyleMode.EMPHASIZED`／`NORMAL`／`TEXTUAL`）、工具栏、颜色等设计规范审查见 harmonyos-ui-review skill（`harmonyos-ui-review.md`），本文不重复。[Button][button]
- 优先保留原生按钮的焦点、禁用、反馈和无障碍语义；自定义可点击区域需补齐对应能力。图标按钮提供可理解的无障碍名称，不能只用颜色表达状态。
- **视觉尺寸与点击热区分开检查。** 中文 UX 标准对手机／平板／折叠屏的主要交互热区推荐至少 48vp × 48vp，要求不小于 40vp × 40vp；36vp 的视觉按钮不能直接视为合格热区。穿戴、电脑及智慧屏采用各自的标准。[UX 体验标准][ux]
- 标签／选择块的形状、选中态、换行和截断按语义设计；使用胶囊按钮时让文本、内边距和可用宽度共同决定尺寸，不强制等宽或套用圆形图标按钮规格。
- 使用系统 Symbol 时查当前官方符号目录、资源预览和目标 SDK 可用性；不要臆造名称，也不要把某符号在一个版本缺失写成永久不存在。固定的 `id_defined.json` 路径不是所有工具链唯一检索方式。[系统符号][symbols]
- `bindSheet` 的关闭按钮与自定义标题应避免重叠；只有确需自绘关闭或发生冲突时才选择 `showClose: false`，并保留明确关闭、系统返回和焦点恢复路径。关闭按钮尺寸及位置会受版本影响，不固定套用旧数值。[半模态接口][sheet]
- 官方提供 Web 与 bindSheet 等父容器的嵌套滚动方案；按 `nestedScroll`、弹层档位、内容尺寸和返回手势配置并验证。复杂长流程可改用独立页面。[Web 嵌套滚动][webscroll]
- 模态层出现时明确事件遮罩和关闭区域，避免误触底层；非模态面板则按设计允许背景交互。不要无差别把所有透明区域设为拦截，也不要让滑块或手势层吞掉无关区域。
- 文案简洁、明确、前后一致，优先提供用户决策所需的状态、错误和下一步；删除重复解释，保留必要帮助。品牌、内部标识的展示策略和术语由项目定义；不建议使用中圆点。[界面用语][wording]

## 8. 手势、坐标与交互状态

- 简单手势使用官方声明式绑定；复用或动态配置可使用 API 12 起的 `GestureModifier` 及对应 Handler。不要把普通函数返回的伪 DSL 当作已注册手势；也不要因一次注册遗漏而禁止全部复用方式。[动态手势][gesture]
- `gestureModifier` 按当前约束绑定实际系统组件，不能直接用于自定义组件或在 `attributeModifier` 内随意嵌套。判断成功的依据是实际触发与冲突处理，不是产物中必须出现某个内部 `create` 调用。[动态手势][gesture]
- 明确事件坐标属于组件、窗口还是显示区域，并处理缩放／平移转换。把手势放在未变换外层是一种有效方案；使用变换层坐标时也可正确换算。
- 点击、双击、拖动、缩放、滚动和系统返回之间的优先级、互斥与并行关系须验证。单指平移、缩放阈值和翻页规则由实际交互决定。
- 使用回调类型正式提供的触点字段；例如 `tapLocation` 从 API 20 起支持，适用于点击手势且要处理无值，不能推广给全部手势；`fingerList` 要检查空数组及无效项，官方建议优先使用有效触点列表 `fingerInfos`。覆盖连续操作、跨组件命中、缩放后点按和弹层遮挡，不能只测试坐标计算函数。[手势事件][gestureevent]

## 9. 生命周期、异步任务和资源所有权

- 新代码在最低版本允许时采用官方推荐的生命周期装饰器：API 23 起（自 `@kit.ArkUI` 导入）有 `@ComponentInit`、`@ComponentAppear`、`@ComponentBuilt`、`@ComponentDisappear`、`@ComponentReuse`、`@ComponentRecycle`；API 26 起另有 `@ComponentActive`／`@ComponentInactive`。低版本或既有实现按适用生命周期维护；迁移时避免新旧回调重复执行同一副作用，请求和订阅不要在 `build()` 中反复启动。[推荐生命周期][lifecycle]
- **销毁、页面隐藏、后台、复用回收、非激活与不可见不是同一个事件。** 不只在 `aboutToDisappear()` 或 `@ComponentDisappear` 清理。页面独占任务、后台允许继续的任务和共享任务分别确定取消／暂停时机；激活状态也不能直接作为曝光或“已阅读”证明。[推荐生命周期][lifecycle]
- 页面／业务身份或查询条件改变时，为请求分配代次或身份标记，拒收迟到结果。取消底层请求与阻止旧回调写入状态必须同时考虑；重试、分页和刷新不能混用不同查询快照。
- 使用 `@kit.NetworkKit` 中 `http` 时，每个 `HttpRequest` 按 API 约定管理。`destroy()` 会终止请求任务并释放资源，正常结束、失败与取消路径均要清理；不要依赖 GC 及时释放。请求对象销毁后不可继续复用。共享任务只由所有者取消，不因一个列表项离屏就中断所有消费者。[HTTP API][http]
- 原生资源明确创建者、持有者、缓存和释放责任。`PixelMap` 释放前确认渲染、解码、导出和其他异步操作都已结束，不再有消费者。[PixelMap][pixelmap]
- **读取图片尺寸不是有效性锁。** `getImageInfoSync()` 可能因资源不可用而失败；检查 `info.size.height > 0` 不能阻止提前释放、重复释放或并发竞态。用所有权约束、幂等清理和适当异常处理保证安全；按用途、尺寸及内存预算管理解码与缓存。[PixelMap][pixelmap] [图片常见问题][image]
- 文件句柄、订阅、计时器和事件监听在对应生命周期释放；重入与失败路径也应可重复清理。I/O 和耗时计算避免阻塞 UI 线程。
- 局部条目失败优先局部呈现并允许重试；整页不可用时才进入整页错误态。已有内容和缓存是否保留由业务一致性要求决定，不应把失败伪装成空结果。
- 修改隐私窗口、权限或持久化配置等异步状态，以实际结果更新界面。日志不泄露凭据、令牌、完整敏感响应或个人信息。

生命周期写法示意（API 23+，片段放入自定义组件；导入来自 `@kit.ArkUI`）：

```ts
import { ComponentDisappear } from '@kit.ArkUI';

// 自定义组件内部：
@ComponentDisappear
onDispose(): void {
  // 幂等释放由该组件独占的资源；不要在此回调中随意修改 UI 状态。
}
```

## 10. 可迁移的业务与交互经验

以下为通用工程建议，具体产品可以有合理例外，不视为鸿蒙 API 限制；产品专属落地写在项目 AGENTS.md。

- 多来源／多账号聚合时，业务键包含足以消歧的命名空间；来源设置与全局设置明确作用域。
- 原始标识、查询值与展示文字分开保存；外部服务经适配边界转换。
- 正在编辑的条件、已提交的查询及其分页游标分离；查询切换、取消和离页使旧结果失效。
- 浏览、选择与批量管理模式明确区分，共享同一状态源。
- 展示、曝光、完成、历史、进度分别定义事件，“已请求”不等于“已看到”。
- 发现共性问题后，按“现象 → 原因 → 适用条件／版本 → 修复原则 → 最小验证 → 官方依据”记录，并定期删除被官方能力替代的绕过方案。

## 11. 官方中文参考


<!-- 版本与兼容 -->
[version]: https://developer.huawei.com/consumer/cn/doc/doccenter-release-notes/upgrade-adaptation
[compat]: https://developer.huawei.com/consumer/cn/doc/doccenter-release-notes/arkts-api-compatibility-warning-elim

<!-- ArkTS 语言与状态管理 -->
[types]: https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/typescript-to-arkts-migration-guide
[observed]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-new-observedv2-and-trace
[state]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-state-management-overview
[binding]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-new-binding
[builder]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-builder
[foreach]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-rendering-control-foreach

<!-- 导航、窗口与布局 -->
[navigation]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-router-to-navigation
[layout]: https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/design-layout-basics-0000001795579413
[hdsnav]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ui-design-hdsnavigation
[hdstabs]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ui-design-hdstabs
[window]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/arkts-apis-window-window
[uicontext]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/arkts-apis-uicontext-uicontext
[windowstage]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/arkts-apis-window-windowstage
[size]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-universal-attributes-size
[repeat]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-new-rendering-control-repeat
[lazyflow]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-container-lazyvwaterflowlayout
[waterflow]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-container-waterflow
[scroll]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-container-scroll
[position]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-universal-attributes-location
[global]: https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/design-globalization-0000001748539688

<!-- HDS、沉浸光感 -->
[tabs]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-container-tabs
[material]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sense-enable
[hdsmaterial]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/ui-design-hds-component-material
[materialattr]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-universal-attributes-image-effect
[uimaterial]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/arkts-apis-uimaterial

<!-- 控件、弹层与文案 -->
[button]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-basic-components-button
[ux]: https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/ux-guidelines-general-0000001760708152
[symbols]: https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/system-icons-0000001929854962
[sheet]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-universal-attributes-sheet-transition
[webscroll]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/web-nested-scrolling
[wording]: https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/design-ui-language-0000001795698453

<!-- 手势、生命周期与资源 -->
[gesture]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-universal-attributes-gesture-modifier
[gestureevent]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-gesture-common
[lifecycle]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-custom-components-new-lifecycle
[http]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-http
[pixelmap]: https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/arkts-apis-image-pixelmap
[image]: https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/image-common-mistakes
