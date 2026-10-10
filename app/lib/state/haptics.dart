import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// ═══════════════════════════════════════════════════════════
///  震动（docs/22 R3）—— 原型 `util.js:123` 的 `buzz()` + 15 处波形，逐条照搬
///
///  为什么用 [vibration] 插件而不是系统 `HapticFeedback`：
///  `HapticFeedback` 只有轻/中/重/长四档，**表达不了原型那些节奏**
///  （`[10,60,20]` 启动、`[40,30,60]` 砸印、`[30,50,30,50]` 升级……）。
///  代价是要 `VIBRATE` 权限（已加进 AndroidManifest）。
///
///  三条纪律：
///  1. **永不抛**：没振动器 / 权限被拒 / 平台不支持 → 只记一行日志
///  2. 开关真正生效：[enabled] 由 main.dart 的设置分发写入（原型的
///     `App.settings.haptic`），false 时一次都不调用插件
///  3. 波形是**真源数据**：数值抄自 prototype/opus-v2-dir/js/，别凭感觉调
/// ═══════════════════════════════════════════════════════════
class Haptics {
  Haptics._();

  /// 由设置分发设置（false = 完全不震）
  static bool enabled = true;

  /// 事件 → 波形（毫秒）；单元素 = 单次时长，多元素 = 「震-停-震…」节奏。
  /// 数据源逐条：flows.js:73/155/237/355/387/412/485/527/649 ·
  /// main.js:48 · ui.js:126/238/265/313/346
  static const Map<String, List<int>> patterns = <String, List<int>>{
    'boot': <int>[10, 60, 20], // 启动（flows.js:73）
    'ignite': <int>[6], // 点环（flows.js:155）
    'publish': <int>[12], // 发布钉单（flows.js:237）
    'shutter': <int>[10], // 拍照（flows.js:355）
    'impact': <int>[40, 30, 60], // 结算砸印·重（flows.js:387，稀有度 ≥4）
    'impactLight': <int>[30], // 同上·轻（F~D）
    'crit': <int>[20, 20, 40], // 暴击（flows.js:412）
    'levelup': <int>[30, 50, 30, 50], // 升级（flows.js:485）
    'fail': <int>[60], // 失败（flows.js:527）
    'poke': <int>[8], // 戳她（flows.js:649）
    'tap': <int>[8], // 点按（main.js:48）
    'choose': <int>[8], // 选选项（ui.js:126）
    'land': <int>[18], // 落板（ui.js:238）
    'rank': <int>[20, 30, 50], // 稀有度落定（ui.js:265，目标 ≥5 档）
    'hold': <int>[5], // 按住每 1/8 步（ui.js:313）
    'seal': <int>[30, 40, 60], // 按满接单（ui.js:346）
  };

  /// 按事件名震一下；未知事件静默（不报错、不震）
  static Future<void> buzz(String key) => pattern(patterns[key]);

  /// 直接给一段波形
  static Future<void> pattern(List<int>? p) async {
    if (!enabled || p == null || p.isEmpty) return;
    try {
      if (p.length == 1) {
        await Vibration.vibrate(duration: p.first);
      } else {
        await Vibration.vibrate(pattern: p);
      }
    } catch (e) {
      // 震动不该拖垮任何交互：设备没振动器/权限被拒都只是"没震"
      debugPrint('[haptics] 震动不可用：$e');
    }
  }

  /// 取消当前震动（认输中途松手等场景，等价原型的 `navigator.vibrate(0)`）
  static Future<void> cancel() async {
    try {
      await Vibration.cancel();
    } catch (_) {
      // 同上：静默
    }
  }
}
