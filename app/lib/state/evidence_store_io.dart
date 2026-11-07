import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

/// 证据根目录名（相对 App 文档目录）——
/// 与 `vision_core.dart` `_store` 落盘的 `evidence/q<serial>/…` 同一口径
const String kEvidenceDirName = 'evidence';

Future<String> _defaultDocsPath() async =>
    (await getApplicationDocumentsDirectory()).path;

/// 删掉整个 `evidence/`（重置存档用）。**永不抛**：
/// 照片删不掉不该拦住重置本身，失败只打一行日志。
///
/// 返回 true = 目录已经不在了（删掉了 / 本来就没有），false = 删失败。
/// [docsPath] 只给测试注入临时目录；不传走 path_provider 的文档目录。
Future<bool> wipeEvidence({Future<String> Function()? docsPath}) async {
  try {
    final String docs = await (docsPath ?? _defaultDocsPath)();
    if (docs.isEmpty) return true;
    final Directory dir = Directory(
      '$docs${Platform.pathSeparator}$kEvidenceDirName',
    );
    if (await dir.exists()) await dir.delete(recursive: true);
    return true;
  } catch (e) {
    debugPrint('[evidence] ⚠️ 清理证据目录失败：$e');
    return false;
  }
}
