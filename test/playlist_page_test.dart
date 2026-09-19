import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeromusic/services/audio/audio_controller.dart';
import 'package:zeromusic/ui/components/song_tile.dart';
import 'package:zeromusic/ui/pages/import/import_page.dart';
import 'package:zeromusic/ui/pages/playlist/playlist_page.dart';
import 'package:zeromusic/ui/scaffold/app_side_bar.dart';

import 'helpers.dart';
import 'support/fake_data_layer.dart';

void main() {
  Future<void> pumpPlaylist(WidgetTester tester) async {
    // 加高视图，让全部歌曲行/横向标签栏在一屏内可见（默认 800x600 装不下）。
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final layer = FakeDataLayer();
    await tester.pumpWidget(wrapApp(overrides: fakeDataLayerOverrides(layer)));
    await tester.pumpAndSettle();
  }

  /// 同 [pumpPlaylist]，但额外返回数据层供批量操作断言。
  Future<FakeDataLayer> pumpPlaylistForBatch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final layer = FakeDataLayer();
    await tester.pumpWidget(wrapApp(overrides: fakeDataLayerOverrides(layer)));
    await tester.pumpAndSettle();
    return layer;
  }

  Finder tileOf(String title) => find.widgetWithText(SongTile, title);
  Finder moreOf(String title) => find.descendant(
      of: tileOf(title), matching: find.byIcon(CupertinoIcons.ellipsis));

  testWidgets('全部：渲染全部歌曲行', (tester) async {
    await pumpPlaylist(tester);

    expect(find.byType(SongTile), findsNWidgets(9));
    expect(find.text('夜空中最亮的星'), findsOneWidget);
    expect(find.text('成都'), findsOneWidget);
    expect(find.textContaining('逃跑计划'), findsWidgets);
  });

  testWidgets('艺人：按艺人分组', (tester) async {
    await pumpPlaylist(tester);

    await tester.tap(find.text('Artists'));
    await tester.pumpAndSettle();

    expect(find.text('周杰伦'), findsWidgets);
    expect(tileOf('晴天'), findsOneWidget);
    expect(tileOf('告白气球'), findsOneWidget);
  });

  testWidgets('喜欢：仅显示喜欢歌曲', (tester) async {
    await pumpPlaylist(tester);

    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();

    expect(find.byType(SongTile), findsNWidgets(3));
    expect(tileOf('夜空中最亮的星'), findsOneWidget);
    expect(tileOf('蓝莲花'), findsOneWidget);
    expect(find.text('平凡之路'), findsNothing);
  });

  testWidgets('最近播放：按最近播放时间倒序', (tester) async {
    await pumpPlaylist(tester);

    await tester.tap(find.text('Recently Played'));
    await tester.pumpAndSettle();

    final tiles = tester.widgetList<SongTile>(find.byType(SongTile)).toList();
    expect(tiles.first.song.title, '成都'); // 30 分钟前最近播放
    expect(tiles.last.song.lastPlayedAt, isNull); // 无播放记录排最后
  });

  testWidgets('分类标签：左右滑动切换主分类', (tester) async {
    await pumpPlaylist(tester);

    // 初始「全部」。
    expect(find.text('夜空中最亮的星'), findsOneWidget);

    // 左滑 → 艺人（分组标题出现）。
    await tester.fling(
        find.text('夜空中最亮的星'), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('周杰伦'), findsWidgets);
    expect(tileOf('晴天'), findsOneWidget);
    expect(tileOf('告白气球'), findsOneWidget);

    // 右滑 → 回到全部。
    await tester.fling(find.text('晴天'), const Offset(500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('夜空中最亮的星'), findsOneWidget);
    expect(find.text('周杰伦'), findsNothing);
  });

  testWidgets('分类标签：滑动与胶囊点击双向同步', (tester) async {
    await pumpPlaylist(tester);

    // 胶囊点击仍可切换（同步 PageView 动画）。
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.byType(SongTile), findsNWidgets(3));

    // 左滑切到最近播放（喜欢 → 最近）。
    await tester.fling(
        find.byType(SongTile).first, const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    expect(tileOf('成都'), findsOneWidget);
  });

  testWidgets('分类标签：标签分类下滑动切回主分类', (tester) async {
    await pumpPlaylist(tester);

    // 打开「标签 ▾」选择「开车必备」（预置标签：夜空中最亮的星/平凡之路/成都）。
    await tester.ensureVisible(find.text('Tags ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tags ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开车必备'));
    await tester.pumpAndSettle();
    expect(find.byType(SongTile), findsNWidgets(3));

    // 左滑 → 切到下一个主分类（艺人），标签筛选被清除。
    await tester.fling(
        find.byType(SongTile).first, const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('周杰伦'), findsWidgets);
  });

  testWidgets('分类边界：最近播放页继续左滑进入导入页', (tester) async {
    await pumpPlaylist(tester);

    // 切到最右「最近播放」。
    await tester.tap(find.text('Recently Played'));
    await tester.pumpAndSettle();
    expect(tileOf('成都'), findsOneWidget);

    // 继续左滑（越界）→ 交棒外层切换到导入页。
    await tester.fling(
        find.byType(SongTile).first, const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(ImportPage), findsOneWidget);
  });

  testWidgets('均衡动画：播放中跳动，暂停后停止', (tester) async {
    await pumpPlaylist(tester);

    // 点一首歌开始播放（夜空中最亮的星 id=1）。
    await tester.tap(tileOf('夜空中最亮的星'));
    await tester.pumpAndSettle();

    dynamic eq() => tester
        .widget<Widget>(find.byKey(const ValueKey('equalizer-1'))) as dynamic;
    expect(eq().isPlaying, isTrue);

    // 经迷你条暂停 → 均衡动画停止。
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();
    expect(eq().isPlaying, isFalse);

    // 再播放 → 恢复跳动。
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(eq().isPlaying, isTrue);
  });

  testWidgets('搜索：按歌手/标签名实时过滤', (tester) async {
    await pumpPlaylist(tester);

    await tester.tap(find.byIcon(CupertinoIcons.search));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.pumpAndSettle();
    expect(tileOf('晴天'), findsOneWidget);
    expect(tileOf('告白气球'), findsOneWidget);
    expect(find.text('演员'), findsNothing);

    // 按标签名过滤。
    await tester.enterText(find.byType(TextField), '开车必备');
    await tester.pumpAndSettle();
    expect(tileOf('平凡之路'), findsOneWidget);
    expect(tileOf('成都'), findsOneWidget);
    expect(find.text('演员'), findsNothing);

    // 无结果空状态。
    await tester.enterText(find.byType(TextField), '不存在的歌');
    await tester.pumpAndSettle();
    expect(find.byType(SongTile), findsNothing);
  });

  testWidgets('点按即播：按当前筛选视图整列入队并显示在迷你条', (tester) async {
    await pumpPlaylist(tester);

    await tester.tap(tileOf('夜空中最亮的星'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlaylistPage)),
    );
    final state = container.read(audioControllerProvider);
    expect(state.isPlaying, isTrue);
    expect(state.currentTrack?.title, '夜空中最亮的星');
    // 队列为当前「全部」视图的整列歌曲，而非单曲。
    expect(state.queue, hasLength(9));
    expect(
      state.queue.indexWhere((t) => t.id == state.currentTrack!.id),
      state.currentIndex,
      reason: '点名歌曲位于队列中的正确位置',
    );

    // 迷你条同步显示。
    expect(find.text('夜空中最亮的星'), findsWidgets);
  });

  testWidgets('喜欢切换：右键菜单红心动画并入库', (tester) async {
    await pumpPlaylist(tester);

    await tester.tap(moreOf('平凡之路'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Favorites'));
    await tester.pumpAndSettle();

    // 行内出现红色红心。
    expect(
      find.descendant(
        of: tileOf('平凡之路'),
        matching: find.byIcon(CupertinoIcons.heart_fill),
      ),
      findsOneWidget,
    );

    // 喜欢分类中能看到。
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(tileOf('平凡之路'), findsOneWidget);
  });

  testWidgets('打标签：可勾选标签并在标签分类中筛选', (tester) async {
    await pumpPlaylist(tester);

    await tester.tap(moreOf('夜空中最亮的星'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tag Song'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('健身'));
    await tester.pumpAndSettle();
    // 选择器是多选面板，先点外部关闭再打开「标签 ▾」筛选。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // 打开「标签 ▾」选择健身。
    await tester.ensureVisible(find.text('Tags ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tags ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('健身'));
    await tester.pumpAndSettle();

    expect(find.byType(SongTile), findsOneWidget);
    expect(tileOf('夜空中最亮的星'), findsOneWidget);
    expect(find.text('平凡之路'), findsNothing);
  });

  testWidgets('编辑：修改标题后即时刷新', (tester) async {
    await pumpPlaylist(tester);

    await tester.tap(moreOf('成都'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '成都 (Live)');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('成都 (Live)'), findsOneWidget);
    expect(find.text('成都'), findsNothing);
  });

  testWidgets('删除：二次确认后移除', (tester) async {
    await pumpPlaylist(tester);

    await tester.tap(moreOf('演员'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // 确认弹窗。
    expect(find.text('Delete Song'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(SongTile), findsNWidgets(8));
    expect(find.text('演员'), findsNothing);
  });

  testWidgets('新建标签：创建后可在筛选面板出现', (tester) async {
    await pumpPlaylist(tester);

    // 打开标签筛选面板。
    await tester.ensureVisible(find.text('Tags ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tags ▾'));
    await tester.pumpAndSettle();

    // 面板头部点「新建标签」打开创建弹窗。
    await tester.tap(find.text('New Tag'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '运动');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // 新建成功后标签出现在筛选面板列表中。
    expect(find.text('运动'), findsOneWidget);
  });

  testWidgets('空状态：无歌曲时显示提示', (tester) async {
    final layer = FakeDataLayer(seed: const []);
    await tester.pumpWidget(wrapApp(overrides: fakeDataLayerOverrides(layer)));
    await tester.pumpAndSettle();

    expect(find.byType(SongTile), findsNothing);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('批量编辑：进入多选并显示已选数量', (tester) async {
    await pumpPlaylistForBatch(tester);

    // 进入批量编辑模式。
    await tester.tap(find.byIcon(CupertinoIcons.square_list));
    await tester.pumpAndSettle();
    expect(find.text('Selected 0'), findsOneWidget);
    // 行内 ⋯ 隐藏，仅保留 AppBar 的批量 ⋯。
    expect(find.byIcon(CupertinoIcons.ellipsis), findsOneWidget);
    // 左侧出现选择圈。
    expect(find.byIcon(CupertinoIcons.circle), findsNWidgets(9));

    // 点按多选。
    await tester.tap(tileOf('平凡之路'));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('成都'));
    await tester.pumpAndSettle();
    expect(find.text('Selected 2'), findsOneWidget);

    // 关闭批量编辑。
    await tester.tap(find.byIcon(CupertinoIcons.xmark));
    await tester.pumpAndSettle();
    expect(find.text('Selected 2'), findsNothing);
    expect(find.byIcon(CupertinoIcons.square_list), findsOneWidget);
  });

  testWidgets('批量编辑：多选两首后批量喜欢再取消', (tester) async {
    final layer = await pumpPlaylistForBatch(tester);

    await tester.tap(find.byIcon(CupertinoIcons.square_list));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('平凡之路'));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('成都'));
    await tester.pumpAndSettle();

    final pingfanId =
        layer.mediaRepository.songs.firstWhere((s) => s.title == '平凡之路').id;
    final chengduId =
        layer.mediaRepository.songs.firstWhere((s) => s.title == '成都').id;

    // 批量加入喜欢。
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Favorites'));
    await tester.pumpAndSettle();

    expect(
      layer.mediaRepository.songs.firstWhere((s) => s.id == pingfanId).isFavorite,
      isTrue,
    );
    expect(
      layer.mediaRepository.songs.firstWhere((s) => s.id == chengduId).isFavorite,
      isTrue,
    );
    // 行内出现红心。
    expect(
      find.descendant(
          of: tileOf('平凡之路'), matching: find.byIcon(CupertinoIcons.heart_fill)),
      findsOneWidget,
    );

    // 已全部喜欢 → 菜单显示取消喜欢。
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from Favorites'));
    await tester.pumpAndSettle();

    expect(
      layer.mediaRepository.songs.firstWhere((s) => s.id == pingfanId).isFavorite,
      isFalse,
    );
    expect(
      layer.mediaRepository.songs.firstWhere((s) => s.id == chengduId).isFavorite,
      isFalse,
    );
  });

  testWidgets('批量编辑：全选后批量加入喜欢', (tester) async {
    final layer = await pumpPlaylistForBatch(tester);

    await tester.tap(find.byIcon(CupertinoIcons.square_list));
    await tester.pumpAndSettle();

    // 全选。
    await tester.tap(find.byIcon(CupertinoIcons.square));
    await tester.pumpAndSettle();
    expect(find.text('Selected 9'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_square), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to Favorites'));
    await tester.pumpAndSettle();

    expect(layer.mediaRepository.songs.every((s) => s.isFavorite), isTrue);
  });

  testWidgets('批量编辑：多选后批量打标签', (tester) async {
    final layer = await pumpPlaylistForBatch(tester);

    await tester.tap(find.byIcon(CupertinoIcons.square_list));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('平凡之路'));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('成都'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tag Song'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('健身'));
    await tester.pumpAndSettle();

    // 关闭弹层。
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    final tagId = layer.tagRepository.tags.firstWhere((t) => t.name == '健身').id;
    final pingfanId =
        layer.mediaRepository.songs.firstWhere((s) => s.title == '平凡之路').id;
    final chengduId =
        layer.mediaRepository.songs.firstWhere((s) => s.title == '成都').id;
    final qingtianId =
        layer.mediaRepository.songs.firstWhere((s) => s.title == '晴天').id;
    expect(layer.songTagLinks[pingfanId], contains(tagId));
    expect(layer.songTagLinks[chengduId], contains(tagId));
    expect(layer.songTagLinks[qingtianId] ?? const <int>{}, isNot(contains(tagId)));
  });

  testWidgets('批量编辑：多选后批量修改标题', (tester) async {
    final layer = await pumpPlaylistForBatch(tester);

    await tester.tap(find.byIcon(CupertinoIcons.square_list));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('平凡之路'));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('成都'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    // 字段留空表示不修改；仅填写标题。
    await tester.enterText(find.byType(TextField).first, '批量标题');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('批量标题'), findsNWidgets(2));
    expect(
      layer.mediaRepository.songs.where((s) => s.title == '批量标题'),
      hasLength(2),
    );
    // 原标题不再出现。
    expect(find.text('平凡之路'), findsNothing);
    expect(find.text('成都'), findsNothing);
  });

  testWidgets('批量编辑：多选后批量删除', (tester) async {
    final layer = await pumpPlaylistForBatch(tester);

    await tester.tap(find.byIcon(CupertinoIcons.square_list));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('演员'));
    await tester.pumpAndSettle();
    await tester.tap(tileOf('成都'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // 二次确认。
    expect(find.text('Delete Song'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(SongTile), findsNWidgets(7));
    expect(find.text('演员'), findsNothing);
    expect(find.text('成都'), findsNothing);
    expect(layer.mediaRepository.songs, hasLength(7));
  });

  testWidgets('桌面端：宽屏右键打开菜单', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpPlaylist(tester);

    await tester.tap(
      tileOf('平凡之路'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Add to Favorites'), findsOneWidget);
    expect(find.text('Add to Queue'), findsOneWidget);
  });

  testWidgets('桌面端：三点按钮菜单在内容区居中弹出（忽略左侧栏）', (tester) async {
    await pumpPlaylist(tester);
    // pumpPlaylist 已设为移动端小窗，此处再切到桌面宽屏并刷新布局。
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    final windowW = tester.view.physicalSize.width;
    final contentCenterX = AppSideBar.width + (windowW - AppSideBar.width) / 2;

    await tester.tap(moreOf('平凡之路'));
    await tester.pumpAndSettle();

    final menuItemX = tester.getCenter(find.text('Add to Favorites'));

    // 弹框应在内容区（不含左侧栏）水平居中，而非贴近三点按钮/整窗中心。
    final fromContentCenter = (menuItemX.dx - contentCenterX).abs();
    final moreX = tester.getCenter(moreOf('平凡之路')).dx;
    final fromMore = (menuItemX.dx - moreX).abs();
    expect(fromContentCenter, lessThan(100));
    expect(fromContentCenter, lessThan(fromMore));
  });

  testWidgets('点击弹窗外部区域可关闭菜单', (tester) async {
    await pumpPlaylist(tester);

    await tester.tap(moreOf('平凡之路'));
    await tester.pumpAndSettle();
    expect(find.text('Add to Favorites'), findsOneWidget);

    // 弹窗外的角落点击 barrier → 关闭。
    await tester.tapAt(const Offset(60, 60));
    await tester.pumpAndSettle();

    expect(find.text('Add to Favorites'), findsNothing);
  });
}