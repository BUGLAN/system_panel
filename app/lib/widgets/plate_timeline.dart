/// ═══════════════════════════════════════════════════════════
///  派单揭晓的时间线（原型 `Plate.rankRoll` / `Plate.engrave` 的两个循环）
///
///  抽成纯函数是有原因的：这两个循环里全是 `await sleep(...)`，
///  直接照抄成 `Future.delayed` 的话，`flutter test` 的假时钟推不动它们
///  （PORTING-NOTES #23）。改成"给一个时刻 t，算出该显示成什么样"，
///  时序就能单测钉死，界面只需要一个控制器从头播到尾。
/// ═══════════════════════════════════════════════════════════
library;

/// 稀有度七档（`content.js` `RANKS`）
const List<String> kRanks = <String>['F', 'E', 'D', 'C', 'B', 'A', 'S'];

/// `Plate.rankRoll(r, from = 0, down = false)` 的向上滚
///
/// ```js
/// for (let i = from; i <= target; i++) {
///   set(i); Sound.play('rung', i);
///   if (i < target) {
///     let d = (60 + i * 26) * (this.fast ? .6 : 1);
///     if (target === 6 && i === 5) d = 560;   // S：在 A 停一拍
///     await sleep(d);
///   }
/// }
/// ```
class RankRollTimeline {
  RankRollTimeline({required this.target, this.from = 0, this.fast = false});

  final int target;
  final int from;
  final bool fast;

  /// 第 i 级停留多久再往上滚（原型那个 `d`）
  double dwellMs(int i) {
    if (target == 6 && i == 5) return 560; // 顶档 S：在 A 上多停一拍
    return (60 + i * 26) * (fast ? .6 : 1);
  }

  /// 第 i 级出现的时刻（ms）
  double startOf(int i) {
    double t = 0;
    for (int k = from; k < i; k++) {
      t += dwellMs(k);
    }
    return t;
  }

  /// 整段滚完要多久（末级不再等）
  double get total => startOf(target);

  /// `t` 时刻应该显示到第几级（0 基）
  int indexAt(double t) {
    int i = from;
    while (i < target && t >= startOf(i + 1)) {
      i++;
    }
    return i;
  }
}

/// `Plate.engrave()` 的逐段激光刻字
///
/// ```js
/// for (const e of els) {
///   const dur = clamp((e.textContent || '').length * 17, 110, 460) * (this.fast ? .55 : 1);
///   ... k 从 0 走到 1，走完这一段再走下一段
/// }
/// ```
class EngraveTimeline {
  EngraveTimeline(this.textLengths, {this.fast = false});

  /// 每段被刻的文字长度（原型用 `e.textContent.length`）
  final List<int> textLengths;
  final bool fast;

  /// 单段时长
  double durOf(int i) =>
      (textLengths[i] * 17).clamp(110, 460) * (fast ? .55 : 1);

  /// 第 i 段开始的时刻（ms）
  double startOf(int i) {
    double t = 0;
    for (int k = 0; k < i; k++) {
      t += durOf(k);
    }
    return t;
  }

  double get total {
    double t = 0;
    for (int i = 0; i < textLengths.length; i++) {
      t += durOf(i);
    }
    return t;
  }

  /// 第 i 段在 `t` 时刻刻到哪了（0~1）
  double kAt(int i, double t) => ((t - startOf(i)) / durOf(i)).clamp(0.0, 1.0);

  /// 此刻正在刻的是第几段；全刻完返回 -1
  int activeAt(double t) {
    for (int i = 0; i < textLengths.length; i++) {
      if (t < startOf(i) + durOf(i)) return i;
    }
    return -1;
  }

  /// 某一段此刻该不该带 `.hot`（刻完 420ms 内还热着 —— 原型那段 `setTimeout`）
  bool hotAt(int i, double t) {
    final double done = startOf(i) + durOf(i);
    return t >= startOf(i) && t <= done + 420;
  }
}

/// 环形刻度：`strokeDashoffset = 226 * (1 - (i + 1) / 7)`
/// （CSS `.pl-rank .ring .fgc { stroke-dasharray: 226 }`，圆周长就是 226）
double rankRingOffset(int index) => 226 * (1 - (index + 1) / 7);
