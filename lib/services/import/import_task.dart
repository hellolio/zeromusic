import 'package:flutter/foundation.dart';

import 'import_source.dart';

/// 导入任务状态。
enum ImportTaskStatus {
  /// 排队等待（顺序队列，一次处理一个）。
  queued,

  /// 正在导入。
  importing,

  /// 已完成并入库。
  completed,

  /// 失败，可重试。
  failed,
}

/// 单条导入任务（内存态，不落库 —— 《07_数据库设计》设计原则 5）。
@immutable
class ImportTask {
  const ImportTask({
    required this.id,
    required this.fileName,
    required this.source,
    this.sourcePath,
    this.targetPath,
    this.coverPath,
    this.status = ImportTaskStatus.queued,
    this.progress = 0,
    this.error,
  });

  /// 唯一任务 id。
  final String id;

  /// 展示用的文件名（含扩展名）。
  final String fileName;

  final ImportSource source;

  /// 源文件路径（移动端为系统给的临时/缓存路径；重试时仍需使用）。
  final String? sourcePath;

  /// 拷贝到应用文档目录后的持久路径。
  final String? targetPath;

  /// 保存到本地的封面路径。
  final String? coverPath;

  final ImportTaskStatus status;

  /// 0..1 进度。
  final double progress;

  /// 失败原因（调试用，UI 只显示通用提示）。
  final String? error;

  bool get isActive =>
      status == ImportTaskStatus.queued || status == ImportTaskStatus.importing;

  bool get isCompleted => status == ImportTaskStatus.completed;

  bool get isFailed => status == ImportTaskStatus.failed;

  ImportTask copyWith({
    String? sourcePath,
    String? targetPath,
    String? coverPath,
    ImportTaskStatus? status,
    double? progress,
    String? error,
  }) {
    return ImportTask(
      id: id,
      fileName: fileName,
      source: source,
      sourcePath: sourcePath ?? this.sourcePath,
      targetPath: targetPath ?? this.targetPath,
      coverPath: coverPath ?? this.coverPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }
}