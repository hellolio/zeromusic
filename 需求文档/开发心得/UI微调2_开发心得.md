# UI 微调 2 · 开发心得

> 功能：底栏/迷你条雾基色分模式 / 播放页队列·音量弹窗雾色带修复 / 均衡器弹窗宽度 / 桌面侧栏去玻璃 / 桌面迷你条收窄。测试全部通过后编写。

## 踩坑与解法

### 1. 「中间一条黑线」的根因：tint 只染雾渐变的中段
- **现象**：播放页只有队列、音量两个弹窗「背景中间有一条黑色横线」，其他弹窗没有。
- **排查捷径**：**某组件独有的问题，先找它独有的参数**。全项目搜 `tint:` 发现只有这两个弹窗传了——`GlassOverlay` 的雾体是三段纵向渐变（基色→tint→基色），`tint` 只替换**中段**；队列弹窗传 `black@0.55`、音量窗深色传 `black@0.4`，中段比上下两段深一大截，灰→黑→灰的过渡在视觉上就是「中间一条黑带」。
- **解法**：一行删除——不传 `tint`，两个弹窗回归与其他弹窗一致的统一灰雾（睡眠定时弹窗同款，正是用户认可的样子）。白色系文字主题（`GlassPopupTextTheme`）保留，可读性不受影响。
- **教训**：`tint` 的「只染中段」语义是为侧栏选中 pill 设计的（中段亮、上下融入灰雾），放进大尺寸弹窗就会变成色带。同一参数在不同尺寸的容器上语义观感完全不同。

### 2. 灰雾玻璃的反噬：雾基色把文字「压灰」
- **现象**：底栏和迷你条的文字在浅色/深色背景下都不够清晰，用户点名「浅色下更白、深色下更黑，而不是浅灰色」。
- **根因**：雾基色 `glassFog = #8E8E93`（systemGray）在上一轮是「正确显灰」的功臣，但在文字对比场景成了减分项：浅色下玻璃读作浅灰、未选中文字也是同级灰，叠在一起就糊。
- **解法**：`GlassOverlay` 新增 `fogColor` 参数——只替换雾的**基色**（上/中/下三段），透明度仍由 `_GlassSpec` 标定；底栏与迷你条（移动+桌面共 3 处）按亮度传 `Colors.white` / `Colors.black`，默认路径（不传）行为零变化。
- **为什么不动全局**：弹窗内文字被 `GlassPopupTextTheme` 统一为白色系（因为弹窗背后叠了暗 barrier、玻璃偏暗），若全局把浅色玻璃改白，白字立刻不可读——牵一发动全身。**局部问题用局部参数解决，全局材质保持稳定**。

### 3. 内容自适应宽度的边界：短文案分支会把弹窗收窄
- **现象**：均衡器「不支持」弹窗只有一段说明文字，窗口被内容收缩得过窄，与其他弹窗宽度不一致。
- **根因**：`showCenterPopup` 用 `maxWidth` 钳制、内容自适应——列表型弹窗内部是 `ListTile`（天生撑满）所以总能到 440；纯文本分支没有撑宽的元素。
- **解法**：`showCenterPopup` 新增 `width` 参数（`minWidth = maxWidth = min(width, 屏宽 80%)`），并把默认上限提为常量 `centerPopupWidth = 440` 供均衡器引用。其他十几处调用不传该参数，零影响。
- **教训**：固定宽度要同时设 `minWidth`，只给 `maxWidth` 对短内容无效；钳制必须保留（小屏 80% 上限），否则固定 440 在窄屏上溢出。

### 4. Flutter 3.47 测试里切深色模式
- `tester.view.platformBrightness` 的 **setter 已被移除**（3.19 废弃后删除），直接赋值编译不过。
- **正解**：`tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark`，清理用 `clearPlatformBrightnessTestValue`。注意要在 `pumpWidget` **之前**设置（本应用 `themeMode` 默认 system，跟随 MediaQuery 亮度），设完再 pump 一次即可构建出深色树。

### 5. 拆玻璃容器时留心 Material 祖先
- 侧栏导航项原来套 `GlassOverlay`，其内部自带一层 `Material(transparent)`；直接换成 `DecoratedBox` 后 `InkWell` 失去最近的 Material 会炸 ink splash。
- 本例安全：侧栏在 `Scaffold` body 内，Scaffold 自带 Material 兜底。但若在无 Material 祖先的裸 Overlay/Stack 里做同样替换，需要自己补一层。**替换「自带脚手架」的组件时，先列出它顺带提供的环境**。

### 6. 回归测试锁「参数」比锁「像素」更稳
- 本轮 5 个新回归测试全部锁结构参数而非渲染像素：`fogColor` 是否按模式取白/黑、弹窗 `tint == null`、弹窗宽度 == `centerPopupWidth`、迷你条宽 380、侧栏项内 `GlassOverlay findsNothing`。
- 相比截图像素对比，这类断言对 Impeller/平台渲染差异免疫，且失败信息直接指向被改坏的参数。UI 视觉效果（白多少、黑多少）仍留给手工验收，测试只防「机制回退」。
