# 弹窗间距 / 底栏水滴滑块 / 迷你条高度 调整

> 已获用户批准（2026-09-20）。切换到 build 模式后按本清单执行。
> 完成后：`flutter analyze` + `flutter test` 全量通过；提交信息「弹窗间距与迷你条优化」。

## 1. 弹窗间距（队列弹窗 + 其他列表型弹窗）

病因：
- 队列弹窗标题下沿 padding 16px + 非 dense 两行 ListTile（行高 72，内容居中再空 ~14px）→ 标题与首行间隙 ~30px。
- 列表型弹窗内包 `SafeArea`：居中浮层不需要，会把手机状态栏(~59px)/底部横条(~34px)高度塞进弹窗内部。

### lib/ui/pages/player/player_page.dart
- `_showQueueSheet`（~L1421）：标题 `Padding(EdgeInsets.all(AppTokens.spaceM))` → `fromLTRB(spaceM, spaceM, spaceM, spaceS)`。
- `_QueueRow`（~L1470）：`ListTile` 加 `dense: true`（行高 72→52，与睡眠定时等弹窗一致）。
- `_showSleepTimerSheet`（~L1223）：移除 `SafeArea` 一层嵌套；标题 padding 同上改 `fromLTRB`。

### lib/ui/pages/settings/settings_sheets.dart
- `_ChoiceSheet`（~L155）：移除 `SafeArea`；标题 padding → `fromLTRB(spaceM, spaceM, spaceM, spaceS)`。

### lib/ui/pages/playlist/playlist_menus.dart
- `showSongMenu`（~L33）、`showBatchSongMenu`（~L101）：移除 `SafeArea`（纯 ListTile 列表，无标题）。
- `_TagPickerSheet`（~L407）、`_TagFilterSheet`（~L499）、`_ManageTagsSheet`（~L708）：移除 `SafeArea`；标题 `Padding(all(spaceM))` → `fromLTRB(spaceM, spaceM, spaceM, spaceS)`。

### lib/ui/pages/player/lyrics_editor.dart
- `_LyricsEditorBody`（~L65）：仅移除 `SafeArea`（标题 padding 已是紧凑式）。

### lib/ui/pages/import/import_source_sheet.dart
- GlassOverlay padding `fromLTRB(24, 16, 24, 32)` → 底部 32 改 24。

## 2. 底栏滑块「水滴」手感（lib/ui/scaffold/glass_nav_bar.dart）

- 新增常量 `static const double _pressScale = 1.12;`（46 高 → 51.5，62 高栏内不裁剪；320 窄屏 itemWidth≈96 > 87 安全）。
- 新增状态 `bool _pressed = false;`。
- 用 `Listener` 包裹现有 `GestureDetector`：`onPointerDown/onPointerUp/onPointerCancel` → `setState(() => _pressed = ...)`（值未变时不重建）。
- 指示胶囊处再嵌一层 `TweenAnimationBuilder<double>`（end：`_pressed && !MediaQuery.disableAnimationsOf(context) ? _pressScale : 1.0`，duration `AppCurves.quickMotion`，curve `AppCurves.spring`），与现有 stretch 的 TweenAnimationBuilder 嵌套，最终 Transform：
  `sx = (1.0 + stretch) * pressScale`、`sy = (1.0 - stretch * 0.35) * pressScale`。
- 拖拽液态拉伸机制不变，与按住放大叠加；尊重减弱动效。

## 3. 迷你条高度调小（移动端 + 桌面端）

- lib/core/theme/app_tokens.dart：`mobileMiniPlayerHeight` 54 → 50（内容 46px 仍放下；adaptive_scaffold 底部留白自动跟随）。
- lib/ui/mini_player/mini_player.dart `_DesktopMiniPlayer`：GlassOverlay padding `vertical: AppTokens.spaceS` → `vertical: 6`（整体 ~60 → 56）。
- 不改 `mobileBottomControlHeight`（底栏 62 保持）。

## 4. 测试

- test/widget_test.dart 新增：按下底栏任意位置 → 滑块 Transform 缩放 > 1（给 Transform 加 `ValueKey('nav-bar-pill-transform')` 读取 `storage[0]`），松手 pumpAndSettle 后回到 1.0。
- 现有 `widget_test.dart`（拖拽切页）、`player_page_test.dart`（TC-09/TC-10 队列用 ListTile 定位，加 dense 不影响）应保持通过。

## 5. 文档（仓库规范）

- 新增 `需求文档/测试用例/UI微调_测试用例.md`、`需求文档/开发心得/UI微调_开发心得.md`（轻量），并按 index.md 规则更新两个目录的 index（如需）。
