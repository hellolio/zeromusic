// 测试夹具：仅供 widget/数据测试使用，生产代码不含任何假数据。
// 移自 lib/data/database/demo_fixtures.dart（生产端已删除播种逻辑）。

/// 一首演示歌曲的元数据。
class DemoSong {
  const DemoSong({
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.durationMs,
    required this.filePath,
    required this.createdAt,
    this.isFavorite = false,
    this.lastPlayedAt,
  });

  final String title;
  final String artist;
  final String album;
  final String genre;
  final int durationMs;
  final String filePath;
  final int createdAt;
  final bool isFavorite;
  final int? lastPlayedAt;
}

const demoTags = [
  ('开车必备', 0xFF2E7D32),
  ('健身', 0xFFF57C00),
  ('治愈', 0xFF9C27B0),
];

const demoSongTags = [
  ('夜空中最亮的星', '开车必备'),
  ('夜空中最亮的星', '治愈'),
  ('平凡之路', '开车必备'),
  ('蓝莲花', '治愈'),
  ('成都', '开车必备'),
  ('成都', '治愈'),
];

List<DemoSong> get demoSongs {
  final now = DateTime.now().millisecondsSinceEpoch;
  const day = Duration.millisecondsPerDay;
  const hour = Duration.millisecondsPerHour;

  return [
    DemoSong(
      title: '夜空中最亮的星',
      artist: '逃跑计划',
      album: '世界',
      genre: '摇滚',
      durationMs: 255000,
      filePath: '/demo/escape-plan-brightest-star.mp3',
      createdAt: now - 9 * day,
      isFavorite: true,
      lastPlayedAt: now - hour,
    ),
    DemoSong(
      title: '平凡之路',
      artist: '朴树',
      album: '猎户星座',
      genre: '民谣',
      durationMs: 268000,
      filePath: '/demo/pushu-ordinary-road.mp3',
      createdAt: now - 8 * day,
    ),
    DemoSong(
      title: '光年之外',
      artist: '邓紫棋',
      album: '光年之外',
      genre: '流行',
      durationMs: 235000,
      filePath: '/demo/gem-light-years.mp3',
      createdAt: now - 7 * day,
      isFavorite: true,
    ),
    DemoSong(
      title: '晴天',
      artist: '周杰伦',
      album: '叶惠美',
      genre: '流行',
      durationMs: 269000,
      filePath: '/demo/jay-qing-tian.mp3',
      createdAt: now - 6 * day,
      lastPlayedAt: now - 5 * hour,
    ),
    DemoSong(
      title: '演员',
      artist: '薛之谦',
      album: '绅士',
      genre: '流行',
      durationMs: 250000,
      filePath: '/demo/xuezhiqian-actor.mp3',
      createdAt: now - 5 * day,
    ),
    DemoSong(
      title: '蓝莲花',
      artist: '许巍',
      album: '时光·漫步',
      genre: '摇滚',
      durationMs: 270000,
      filePath: '/demo/xuwei-blue-lotus.mp3',
      createdAt: now - 4 * day,
      isFavorite: true,
      lastPlayedAt: now - 2 * day,
    ),
    DemoSong(
      title: '告白气球',
      artist: '周杰伦',
      album: '周杰伦的床边故事',
      genre: '流行',
      durationMs: 215000,
      filePath: '/demo/jay-balloon.mp3',
      createdAt: now - 3 * day,
    ),
    DemoSong(
      title: '小幸运',
      artist: '田馥甄',
      album: '小幸运',
      genre: '流行',
      durationMs: 260000,
      filePath: '/demo/hebe-lucky.mp3',
      createdAt: now - 2 * day,
    ),
    DemoSong(
      title: '成都',
      artist: '赵雷',
      album: '无法长大',
      genre: '民谣',
      durationMs: 355000,
      filePath: '/demo/zhaolei-chengdu.mp3',
      createdAt: now - day,
      lastPlayedAt: now - 30 * Duration.millisecondsPerMinute,
    ),
  ];
}