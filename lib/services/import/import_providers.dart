import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'import_service.dart';

/// 全局导入调度器。
final importControllerProvider =
    NotifierProvider<ImportService, ImportState>(ImportService.new);