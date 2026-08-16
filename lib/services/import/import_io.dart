import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 导入 IO 的领域值对象与可注入接口。
/// 真实实现调用 file_picker / path_provider / audio_metadata_reader；
/// 测试注入内存假实现，不触碰真实文件系统与平台插件。

/// 选择器返回的一个音频文件。
class PickedAudioFile {
  const PickedAudioFile({required this.name, this.path});

  /// 文件名（含扩展名）。
  final String name;

  /// 本地文件路径；为 null 表示无法从磁盘读取（如网页端）。
  final String? path;
}

/// 元数据读取结果（DTO，供导入入库使用）。
class ImportAudioMetadata {
  const ImportAudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.durationMs = 0,
    this.coverBytes,
    this.coverMime,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int durationMs;

  /// 封面图像字节（可能为大图，读取时按需）。
  final Uint8List? coverBytes;
  final String? coverMime;
}

/// 导入失败（复制/元数据解析等文件层错误）。
class ImportException implements Exception {
  const ImportException(this.message);

  final String message;

  @override
  String toString() => 'ImportException: $message';
}

/// 通过系统原生选择器挑选音频文件。
abstract class ImportFilePicker {
  /// 返回空列表表示用户取消。
  Future<List<PickedAudioFile>> pickAudioFiles();
}

/// 真实实现：file_picker（移动 + 桌面全平台，扩展名过滤、多选）。
class PlatformImportFilePicker implements ImportFilePicker {
  /// 支持的音频扩展名（覆盖 04 文档格式清单）。
  static const supportedExtensions = [
    'mp3',
    'flac',
    'wav',
    'm4a',
    'mp4',
    'ogg',
    'opus',
    'aac',
    'aiff',
    'aif',
    'ape',
  ];

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );
    return [
      for (final f in files) PickedAudioFile(name: f.name, path: f.path),
    ];
  }
}

/// 文件存储：把导入文件拷贝到应用文档目录、保存封面（决定歌曲的持久路径）。
abstract class ImportFileStore {
  /// 拷贝 [file] 到持久目录，返回目标路径（自动处理同名冲突）。
  Future<String> copy(PickedAudioFile file);

  /// 保存封面字节，返回封面文件路径。
  Future<String?> saveCover(Uint8List bytes, String extension);
}

/// 真实实现：path_provider 应用文档目录 + dart:io。
class AppImportFileStore implements ImportFileStore {
  Future<Directory> get _base async =>
      getApplicationDocumentsDirectory();

  Future<Directory> _subDir(String name) async {
    final base = await _base;
    final dir = Directory(p.join(base.path, name));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<String> copy(PickedAudioFile file) async {
    final source = file.path;
    if (source == null) {
      throw const ImportException('无法从所选文件读取本地路径');
    }
    final dir = await _subDir('imports');
    final target = _uniquePath(dir, file.name);
    await File(source).copy(target);
    return target;
  }

  @override
  Future<String?> saveCover(Uint8List bytes, String extension) async {
    if (bytes.isEmpty) return null;
    final dir = await _subDir('covers');
    final name = 'cover-${DateTime.now().millisecondsSinceEpoch}.$extension';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 同名文件追加 " (n)" 计数，保证 copy 后路径唯一（songs.file_path 唯一约束）。
  String _uniquePath(Directory dir, String name) {
    final ext = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    var candidate = name;
    var n = 1;
    while (File(p.join(dir.path, candidate)).existsSync()) {
      candidate = '$stem ($n)$ext';
      n++;
    }
    return p.join(dir.path, candidate);
  }
}

/// 读取音频文件内容（歌名/歌手/专辑/流派/时长/封面）。
abstract class ImportMetadataExtractor {
  Future<ImportAudioMetadata> extract(String filePath);
}

/// 真实实现：audio_metadata_reader（纯 Dart，全平台无原生代码）。
class AudioMetadataExtractor implements ImportMetadataExtractor {
  @override
  Future<ImportAudioMetadata> extract(String filePath) async {
    AudioMetadata meta;
    try {
      meta = readMetadata(File(filePath), getImage: true);
    } catch (_) {
      // 无法解析（未知/损坏格式）→ 用文件名兜底，仍允许入库。
      return ImportAudioMetadata(title: _titleFromPath(filePath));
    }
    final cover = meta.pictures.isNotEmpty ? meta.pictures.first : null;
    return ImportAudioMetadata(
      title: meta.title ?? _titleFromPath(filePath),
      artist: meta.artist,
      album: meta.album,
      genre: meta.genres.isNotEmpty ? meta.genres.first : null,
      durationMs: meta.duration?.inMilliseconds ?? 0,
      coverBytes: cover?.bytes,
      coverMime: cover?.mimetype,
    );
  }

  String _titleFromPath(String filePath) => p.basenameWithoutExtension(filePath);
}

/// ---- Riverpod 提供者（真实实现；测试可用 override 替换） ----
final importFilePickerProvider =
    Provider<ImportFilePicker>((ref) => PlatformImportFilePicker());

final importFileStoreProvider =
    Provider<ImportFileStore>((ref) => AppImportFileStore());

final importMetadataExtractorProvider =
    Provider<ImportMetadataExtractor>((ref) => AudioMetadataExtractor());