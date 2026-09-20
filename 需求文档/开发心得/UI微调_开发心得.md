# UI 微调 · 开发心得

> 功能：弹窗间距压缩 / 底栏水滴滑块 / 迷你条高度收紧。测试全部通过后编写。

## 踩坑与解法

### 1. 居中弹窗里的 SafeArea 是「死空间」制造机，但它也在「顺便」屏蔽另一个 bug
- **现象**：列表型弹窗（歌曲菜单、标签选择、睡眠定时等）在手机上上下各多出 ~59px/34px 的空白。
- **根因**：弹窗经 `showGeneralDialog` + `Center` 居中，但 `SafeArea` 读取的 `MediaQuery.padding` 是整屏安全区——它把状态栏/Home 条高度塞进了居中浮层内部，而浮层根本贴不到屏幕边缘。
- **解法**：全部移除。键盘场景也不受影响（键盘走 `viewInsets`，不走 `padding`）。
- **二次返工教训（本轮最大坑）**：移除 SafeArea 后，播放队列与标签弹窗的空白「复发」。真正根因是 **Flutter `ListView` 在 `padding == null` 时会自动把 `MediaQuery.padding` 当作列表的 `SliverPadding`**（SDK `scroll_view.dart` 注释原文 "Automatically pad sliver with padding from MediaQuery"）：
  - 播放队列弹窗从未有过 SafeArea → 移动端一直吸收状态栏高度（~59px），是最初抱怨的真正主体；
  - 标签弹窗原来靠 SafeArea「顺便」屏蔽了该机制 → 移除 SafeArea 反而把它暴露出来；
  - 桌面端 `MediaQuery.padding` 恒为 0，桌面视口测量永远测不出此 bug（前两轮测量失准的原因）。
- **最终解法（双保险）**：
  1. `showCenterPopup` 的 pageBuilder 用 `MediaQuery.removePadding`（四边）包住弹窗内容——系统性根治，今后弹窗内任何滚动列表都不再吸收安全区高度；
  2. 弹窗内 4 处 `ListView` 显式 `padding: EdgeInsets.zero`（自文档化，离开弹窗上下文也安全）。
  3. 回归测试：模拟状态栏 59px（`tester.view.padding = const FakeViewPadding(top: 59, bottom: 34)`），断言弹窗内 `ListView.padding == EdgeInsets.zero` 且标题→首行间距 ≤ 24px；曾验证去掉修复后该测试确实失败。

### 2. 队列弹窗间隙大的两个叠加来源（含二次返工教训）
- 标题 `Padding.all(16)` 的下沿 + 队列行是**非 dense 两行 ListTile**，标题到首行文本实测 ~30px。
- **教训：M3 的 ListTile 行高由内部规格决定，`dense` 远不够**——dense 两行实测行高 64px（内容仅 ~44px，每行上下各空 ~10px），只加 dense 时标题到首行仍有 23px；必须再加 `visualDensity: VisualDensity.compact`（64→53）才真正收紧。最终：标题到首行文本 **30px → 16px**，行高 **72 → 53**。
- 排查手段：写临时 widget 测试用 `tester.getRect` 实测标题文本与首行文本的像素差，不靠目测猜。

### 3. 迷你条 54→50 直接溢出 4px
- **根因**：胶囊内容两行文本自然高 ~48，原 `Padding(vertical: 3)` 后可用高度只剩 44。
- **解法**：去掉纵向 padding——内容本就靠 `Column(mainAxisAlignment: center)` 垂直居中，padding 只贡献死空间。教训：**收紧容器高度前先算内容的自然高度**。

### 4. widget 测试强制减弱动效 vs 按压反馈
- `wrapApp` 强制 `disableAnimations: true`，最初实现「减弱动效时不放大」导致测试拿到的缩放恒为 1.0。
- **解法**：减弱动效时改为 `duration: Duration.zero` **瞬时到位**——静态状态变化不算动效，既保留按压反馈，又可被测试验证。

### 5. 测试断言要吃 token，不要硬编码派生值
- 「底栏比迷你条高 8px」是 `62 - 54` 的派生值；迷你条改 50 后该断言即碎。
- **解法**：断言改为 `mobileBottomControlHeight - mobileMiniPlayerHeight`，token 变更测试自动跟随。

### 6. Dart 3.13 formatter 会整文件重排
- 本仓库并非 Dart 3.13 tall-style 格式化干净；对改动文件跑 `dart format` 引入了大量无关重排（一个文件 500+ 行 diff）。已回滚并改为手工保持原缩进风格。
- **教训**：对存量代码跑新版 formatter 前先确认仓库是否 format-clean（`dart format --output=none --set-exit-if-changed` 抽查）。

### 7. 环境坑：Xcode 许可证拦截工具链
- Xcode 更新后未接受许可，`flutter`/`dart` 包装脚本、`git`、`xcrun` 全部失败；`objective_c` 包的 native-asset 构建钩子（调 `xcrun --show-sdk-path`）会直接卡死 `flutter test`。
- `sudo xcodebuild -license` 接受后恢复。

## 已知余量 / 未覆盖
- 按压放大的「正常动画路径」（easeOutBack 过冲）在 widget 测试中不可覆盖（环境强制减弱动效），仅手工验证。
- 多指同时按压时先抬一指会提前回弹（纯外观、自愈），可接受。
- 全 app 未钳制 textScaler，极大辅助字号下迷你条可能纵向溢出（改动前已存在）。
