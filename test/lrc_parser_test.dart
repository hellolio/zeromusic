import 'package:flutter_test/flutter_test.dart';
import 'package:zeromusic/services/lyrics/lrc_parser.dart';
import 'package:zeromusic/services/lyrics/lyrics_line.dart';

void main() {
  LyricsLine line(int ms, String text) =>
      LyricsLine(time: Duration(milliseconds: ms), text: text);

  test('解析基础 mm:ss 时间戳', () {
    final lines = parseLrc('[00:12.00]第一句\n[00:45.50]第二句');
    expect(lines, [
      line(12000, '第一句'),
      line(45500, '第二句'),
    ]);
  });

  test('解析 mm:ss 与 mm:ss.xx 混用并按时间排序', () {
    final lines = parseLrc('[00:30]中间\n[00:05.5]开头\n[01:00.123]结尾');
    expect(lines, [
      line(5500, '开头'),
      line(30000, '中间'),
      line(60123, '结尾'),
    ]);
  });

  test('一行多个时间戳展开为多句', () {
    final lines = parseLrc('[00:10.00][00:20.00]重复行');
    expect(lines, [
      line(10000, '重复行'),
      line(20000, '重复行'),
    ]);
  });

  test('忽略元信息标签行', () {
    final lines = parseLrc('[ti:歌名]\n[ar:歌手]\n[al:专辑]\n[00:12.00]正文');
    expect(lines, [line(12000, '正文')]);
  });

  test('offset 全局偏移作用于全部时间戳', () {
    expect(
      parseLrc('[offset:500]\n[00:10.00]行'),
      [line(10500, '行')],
    );
    expect(
      parseLrc('[offset:-200]\n[00:10.00]行'),
      [line(9800, '行')],
    );
  });

  test('剥离内联增强歌词时间戳 <mm:ss.xx>', () {
    expect(
      parseLrc('[00:12.00]<00:12.00>第一个字<00:15.00>第二个字'),
      [line(12000, '第一个字第二个字')],
    );
  });

  test('空文本 / 纯元信息 / 无时间戳 → 空列表', () {
    expect(parseLrc(''), isEmpty);
    expect(parseLrc('   '), isEmpty);
    expect(parseLrc('[ti:只有元信息]'), isEmpty);
    expect(parseLrc('没有时间戳的普通文本'), isEmpty);
  });
}