import 'package:zeromusic/services/preferences/preferences_controller.dart';

/// 测试用内存偏好存储：记录每次保存快照，供持久化断言。
class InMemoryPreferencesStore implements PreferencesStore {
  InMemoryPreferencesStore([
    AppPreferences initial = const AppPreferences(),
  ]) : _current = initial;

  AppPreferences _current;

  /// 每次 [save] 的快照（按调用顺序）。
  final List<AppPreferences> saved = [];

  @override
  Future<AppPreferences> load() async => _current;

  @override
  Future<void> save(AppPreferences prefs) async {
    _current = prefs;
    saved.add(prefs);
  }

  /// 最近一次保存的偏好；未保存过则返回初始值。
  AppPreferences get lastSaved => saved.isEmpty ? _current : saved.last;
}
