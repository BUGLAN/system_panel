/// ═══════════════════════════════════════════════════════════
///  证据照片的清理（G3.2）
///
///  照片由 `agent/vision_core.dart` 落在 App 文档目录 `evidence/q<serial>/…`，
///  原来全仓没有任何删除逻辑 —— 「重置 = 全部清空」对照片不成立。
///
///  宿主定案（2026-11-06）：照片**只在重置存档时清**；结算、认输之后都不删。
///  所以这里只有「删整个 evidence/」一个入口，由 main.dart `_wipe` 调用。
///
///  平台分流照 `agent/vision_platform.dart` 的条件导入写法：
///  IO 删目录；Web 没有落盘（证据只活在内存里），空实现。
/// ═══════════════════════════════════════════════════════════
library;

export 'evidence_store_io.dart'
    if (dart.library.html) 'evidence_store_web.dart';
