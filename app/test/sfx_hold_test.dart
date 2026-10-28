import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/sfx.dart';

/// 音效总线的**槽位保持时长**（docs/41 §4.2）。
///
/// 这条钉子防的是一类「听不出来、但会引发槽位复用错乱」的缺陷：
/// 原来 `_busyHold` 是固定 250ms，按逐字音（~60ms）标定的 ——
/// 于是 `seal`(1.26s) / `impact`(1.29s) / `boot`(3.65s) 全被腰斩：
/// 槽位提前标空闲 → 被下一发复用到**正在播的实例** → 插件层 stop/play 交错。
void main() {
  group('音效槽位保持时长', () {
    test('短音仍是 250ms（逐字音那条高频路不许变慢）', () {
      for (final String k in <String>[
        'tap',
        'choose',
        'detent',
        'deal',
        'rung',
      ]) {
        expect(
          Sfx.holdForTest(k),
          const Duration(milliseconds: 250),
          reason: '$k 是短音，必须留在 250ms —— 变长会饿死打字机逐字音',
        );
      }
    });

    test('长音按素材时长给上界，不再被 250ms 腰斩', () {
      // 素材实测时长（gen_sfx 输出）：seal 1.26s / impact 1.29s
      expect(Sfx.holdForTest('seal').inMilliseconds, greaterThan(1260));
      expect(Sfx.holdForTest('impact').inMilliseconds, greaterThan(1290));
      // docs/49 A6：以下几件换成参考稿版本（ref_*.wav），按新素材时长钉上界
      for (final (String k, int ms) in <(String, int)>[
        ('boot', 1570),
        ('levelup', 1830),
        ('crit', 940),
        ('fail', 890),
        ('success', 740),
        ('unlock', 610),
        ('whoosh', 580),
        ('buy', 460),
        ('stamp', 430),
        ('error', 370),
        ('coin', 295),
        ('hold', 270),
      ]) {
        expect(
          Sfx.holdForTest(k).inMilliseconds,
          greaterThan(ms),
          reason: '$k 素材 ${ms}ms，槽位不能比它先放回池子',
        );
      }
    });

    test('未登记的 key 回落到默认 250ms（新增短音不必改表）', () {
      expect(
        Sfx.holdForTest('no_such_event'),
        const Duration(milliseconds: 250),
      );
    });
  });
}
