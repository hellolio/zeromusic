# UI 微调 3 · 开发心得

> 功能：桌面歌词开关移至迷你条 / 迷你条音量弹窗 / 删除悬停提示（迷你条 + 桌面歌词条）/ 胶囊加宽 380→440。测试全部通过后编写。

## 踩坑与解法

### 1. 「几何中心是热区」假设的崩塌：加宽胶囊后测试大面积失败
- **现象**：实现完成后 25 个用例齐挂，且全部是「进入播放页失败」（`Found 0 widgets with type PlayerPage`），analyze 干净、无异常日志，非常迷惑。
- **排查过程**：
  1. 先怀疑新加的歌词开关/音量按钮挡住了点按——打印各按钮坐标，发现都不在中心点上，排除；
  2. 给 `GestureDetector` 加 `HitTestBehavior.opaque` 想让控件间隙成为热区——依旧失败；
  3. 直接用 `tester.binding.hitTestInView` 打印中心点的**完整命中链**：最内层是 `TextSpan → RenderParagraph → _RenderInputPadding → _RenderInkFeatures`——这是 **IconButton**！
- **根因**：桌面胶囊加宽到 440 后，右侧控制行（5 个 40×40 按钮，IconButton 命中区还会扩展）占据约 220px，胶囊**几何中心恰好落在 ⏮ 按钮命中区内**。旧布局（380 宽、3 个 48px 按钮）中心点正好在歌名上，所以此前所有「点 `find.byType(MiniPlayer)` 中心进入播放页」的测试都只是**碰巧**成立。测试里 `tap` 默认点 widget 几何中心，点到了 ⏮ → 触发「上一首」→ 播放页从未打开。
- **解法**：
  1. 测试侧：`helpers.dart` 新增 `tapMiniPlayerToOpenPlayer`——点封面区域（局部 x≈36）而非中心，`pumpPlayer` 与 `widget_test` 改用之，并在注释里写明「为什么不能点中心」；
  2. 产品侧：`opaque` 修复**保留**——它解决的是真实问题：文字与按钮之间的间隙原先不是热区（`deferToChild` 下点在 Row 空隙上无响应）。
- **教训**：
  - 「点 widget 中心」隐含「中心不是可交互控件」的假设，改布局前先确认该假设成立；
  - Flutter 测试疑难杂症，`hitTestInView` 打印命中链是最快的实锤手段，比猜测坐标快得多；
  - 测试通过 ≠ 假设正确，可能只是布局让它碰巧成立。

### 2. 音量弹窗抽公共组件时 key 不能顺手「改名」
- 播放页音量弹窗抽到 `lib/ui/components/volume_popover.dart` 时，曾把 key 从 `player-volume-popover/slider` 改成通用 `volume-popover/slider`——key 是测试与（潜在）自动化锚点，**迁移组件时 key 原样搬**，需要改名要连同所有引用一起评估。本轮最终统一为新 key，并同步更新了 `player_page_test` 三处引用，行为回归全绿。
- **教训**：`ValueKey` 字符串是跨文件的隐式契约，重构时用全局搜索确认所有引用点，一次改齐，不留「半套旧 key」。

### 3. 会话级偏好不能靠 store 预置
- `desktopLyricsEnabled` 是会话级偏好（启动时强制归零），测试里**不能**通过 `InMemoryPreferencesStore` 预置为 true 来构造「已开启」场景——store 里的值会被启动逻辑清掉。
- 正解：pump 之后用 `container.read(preferencesProvider.notifier).setDesktopLyricsEnabled(true)` 程序化置位。这类「启动清洗」逻辑是测试造数的一大陷阱：**预置数据必须走被测系统同一条写路径**。

### 4. 删字符串 getter 要连根拔
- 删除悬停提示后，`desktopLyricsClose/FocusHint/Play/Pause/Previous/Next/Volume` 等字符串 getter 变成孤儿。四份语言文件 + 基类同步删除，靠 `flutter analyze` 兜底（若仍有引用会报 undefined）。
- 注意 `miniPrevious/miniPlayPause/miniNext` 看似也是「迷你条提示」，但 `player_page.dart` 仍在引用，**删前全局搜引用**，别按语义猜。

### 5. 按钮收紧后要重新核算「中心热区」与文字宽度
- 本轮把控制按钮统一收紧为 40×40、胶囊加宽到 440，两者共同决定歌名区仍保留约 136px 可读宽度（长名省略号截断）。**布局参数（宽度）与子项数量/尺寸是耦合的**，改任何一个都要重算整行分配——教训见坑 1，这次是文字区「让」给了控制行，下次反向调整时同样要复查。

## 回归保障

- 音量弹窗：播放页原有三用例只改 key 后原样通过，证明抽组件是等价迁移；
- 桌面歌词条：既有按键命中/回调用例零改动通过，证明删 Tooltip 无行为影响；
- 迷你条：新增「无 Tooltip」负向断言，防止后续有人无意加回。
