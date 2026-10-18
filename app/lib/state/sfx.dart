import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// ═══════════════════════════════════════════════════════════
///  音效总线（docs/22 R3）—— 素材是**离线烘好的包**（`tools/audio/` 生成，
///  参数照 `prototype/opus-v2-dir/js/audio.js` 那套 Web Audio 规格），
///  事件名与原型 `Sound.play(name)` 一一对应。
///
///  宿主 2026-10-10 裁决：走「预生成音效包」（不是现场合成）。
///
///  三条纪律：
///  1. **永不抛**：素材缺失 / 播放器异常 → 只记一行日志。音效永远不能
///     拖垮交互（与 LLM 那条兜底铁律同源：出错可以，卡住不行）
///  2. **开关真正生效**：[enabled] 由 main.dart 的设置分发写入；false 时
///     连播放器都不碰（原型 `App.settings.sound`）
///  3. 高频事件（打字机逐字 34ms、按住每 1/8 步、EXP 滚数每 55ms）
///     走**池化播放器**，不复用同一个实例——单实例会互相打断
/// ═══════════════════════════════════════════════════════════
class Sfx {
  Sfx._();

  /// 由设置分发设置（false = 完全静音；不碰播放器）
  static bool enabled = true;

  /// 全局音量（0~1）。素材里已经按原型叠好相对响度，这里只做总衰减
  static double volume = 1.0;

  /// 播放失败计数 + 最近一次原因（诊断用）。
  /// 独立验收（task-12）建议：像 LLM 那行一样在设置页回显——这次「池化回归」
  /// 就是靠验收人 grep logcat 才发现的，这种信号不该只活在日志里。
  static int failCount = 0;
  static String? lastError;

  /// 起播超时被丢弃的发数（平台侧 `prepared` 没来；见 `_playFile` 的说明）。
  /// 单独计数、**不当失败**：它是"少响一发"，不是"播放报错"，但也不能瞒着——
  /// 设置页会把它一并回显，开发阶段看得到平台在掉链子。
  static int dropCount = 0;
  static String? lastDrop;

  /// 事件 → 素材路径（相对 `assets/`，`AssetSource` 前缀就是 `assets/`）。
  /// 多条 = 变体：每次随机取一条（原型每发都随机音高，不随机就丢手感）。
  /// 命名约定由 `tools/audio/` 的烘焙脚本保证。
  static const Map<String, List<String>> table = <String, List<String>>{
    // ── 高频 12 件（docs/22 R3-A）──
    'tap': <String>['audio/tap.wav'],
    // 戳她（原型 audio.js L130 `poke` 620→990Hz triangle；flows.js L649 播它）
    'poke': <String>['audio/poke.wav'],
    'choose': <String>['audio/choose.wav'],
    'land': <String>['audio/land.wav'], // 委托单落板
    'rung': <String>[ // 稀有度逐级滚（原型按步进变调 → 烘成 5 档）
      'audio/rung_0.wav',
      'audio/rung_1.wav',
      'audio/rung_2.wav',
      'audio/rung_3.wav',
      'audio/rung_4.wav',
    ],
    'rank': <String>[ // 稀有度落定：原型按 RARITY.i（F~S = 0~6）变调变重
      'audio/rank_0.wav',
      'audio/rank_1.wav',
      'audio/rank_2.wav',
      'audio/rank_3.wav',
      'audio/rank_4.wav',
      'audio/rank_5.wav',
      'audio/rank_6.wav',
    ],
    'ignite': <String>[ // 点亮进度带（唤醒时）：原型 `audio.js:88-91` 分三档变调
      'audio/ignite_0.wav',
      'audio/ignite_1.wav',
      'audio/ignite_2.wav',
      'audio/ignite_3.wav',
      'audio/ignite_4.wav',
      'audio/ignite_5.wav',
      'audio/ignite_6.wav',
      'audio/ignite_7.wav',
    ],
    'seal': <String>['audio/seal.wav'], // 按满接单 / 提交钤印
    'publish': <String>['audio/ding.wav'], // 发布（原型叫 ding，「只属于派单」）
    'impact': <String>['audio/impact.wav'], // 结算砸印
    'count': <String>[ // EXP 滚数（原型每 55ms 一发）
      'audio/count_0.wav',
      'audio/count_1.wav',
      'audio/count_2.wav',
    ],
    'crit': <String>['audio/crit.wav'],
    'levelup': <String>['audio/levelup.wav'],
    'fail': <String>['audio/fail.wav'],
    // docs/41 §1 Bug ③：`boot.wav` **一直在盘上（85 件里的第 1 件）**，
    // 但 `table` 里从来没有这个 key —— 而 `main.dart` 的唤醒流程每次都在调
    // `Sfx.play('boot')`。于是每次唤醒都是一次**空调用**：`_pick` 返回 null、
    // 静默返回、连 `failCount` 都不加，因此这个漏项从来没被任何统计发现。
    'boot': <String>['audio/boot.wav'],
    // ── 底噪（可循环，设置页可关；原型 audio.js 的 ambient）──
    'ambient': <String>['audio/ambient_loop.wav'],
  };

  /// 逐字音节（打字机每个显形字一发）：`syl_<情绪>_<变体>.wav`
  static const List<String> _emotions = <String>[
    'neutral', 'smug', 'cold', 'annoyed', 'pleased', 'tsun',
    'joy', 'proud', 'surprised', 'sad', 'focus', 'sleep',
  ];

  static final Random _rnd = Random();

  // ── 池化播放器 ─────────────────────────────────────────────
  //
  // 三个坑，全在 `.verify/batch2/` 有实机证据（j-summary §3.3 / k-summary §3.4）：
  //   ① **绝不交付"未配置完"的实例**：池里存 `Future<AudioPlayer>`，
  //      交付前 `await`（曾经先占位再配置 → 交出未就绪实例 → play() 永不返回）
  //   ② **绝不复用"正在播"的实例**：6 个实例 + 打字机 34ms 一发，轮转必然重叠，
  //      同一实例上两次 `stop()/play()` 在插件层交错 → 30s 超时、逐字音成片不响。
  //      所以按**忙闲**发牌：全忙且到上限时，**这一发直接不播**（比卡死好得多）。
  //   ③ **上限严格**：`_slots.length` 只在同步路径增长 → 并发再多也 ≤ [_poolSize]
  // 另：**不要用 `Future.delayed` 轮询**（会给 widget 测试留 pending timer）。
  static final List<_Slot> _slots = <_Slot>[];
  static int _next = 0;
  static const int _poolSize = 12;

  /// 一个槽位被占用后保持多久才放回池子（起播后计时）。
  /// 逐字音节约 60ms、`land` 430ms；取 250ms 兜住最高频那条路：
  /// 12 槽 / 250ms = 48 发每秒 > 打字机 29 字每秒（34ms/字），不会饿死。
  static const Duration _busyHold = Duration(milliseconds: 250);

  /// 单发起播的看门狗：超过它就认为这一发起不来了（平台 `prepared` 丢了），
  /// 丢弃这一发 + 把槽踢出池子（audioplayers 自己的超时是 30 秒，太长——
  /// 一发挂住会拖垮整段逐字音）。
  static const Duration _playWatchdog = Duration(milliseconds: 1200);

  /// 建一个**配置完成**的播放器（短音效用低延迟模式：Android 走 SoundPool，
  /// 打字机逐字 34ms 一发才跟得上）
  static Future<AudioPlayer> _create() async {
    final AudioPlayer p = AudioPlayer();
    await p.setPlayerMode(PlayerMode.lowLatency);
    await p.setReleaseMode(ReleaseMode.stop);
    return p;
  }

  /// 取一个**空闲**槽位（已标记 busy）；没有空闲且到上限 → 返回 null（这一发不播）
  static Future<_Slot?> _take() async {
    // ① 先找空闲槽（从 _next 起轮转，保证均匀）
    for (int i = 0; i < _slots.length; i++) {
      final _Slot s = _slots[(_next + i) % _slots.length];
      if (s.busy) continue;
      _next = (_next + i + 1) % _slots.length;
      s.busy = true;
      try {
        await s.ready; // 等配置完（绝不交付未就绪实例）
        return s;
      } catch (_) {
        s.busy = false;
        return null; // 这个槽坏了（例如测试环境无插件）→ 这一发不播
      }
    }
    // ② 全忙：还没到上限就新建（同步占位 → 上限严格）
    if (_slots.length < _poolSize) {
      final _Slot s = _Slot(_create());
      _slots.add(s);
      s.busy = true;
      try {
        await s.ready;
        return s;
      } catch (_) {
        s.busy = false;
        return null;
      }
    }
    // ③ 全忙且到上限：放弃这一发
    return null;
  }

  static String? _pick(String key, int? variant) {
    final List<String>? files = table[key];
    if (files == null || files.isEmpty) return null;
    // 指定档位（如稀有度 i=0..6）：越界就退回中档，绝不越界崩
    if (variant != null) {
      return files[variant.clamp(0, files.length - 1)];
    }
    return files.length == 1 ? files.first : files[_rnd.nextInt(files.length)];
  }

  /// 按事件名播一下；未知事件静默
  ///
  /// [variant] 用于**按档位变调**的事件（目前只有 `rank`：稀有度 F~S = 0~6）。
  /// 传别的 key 无副作用（越界会被 clamp 到列表内）。
  static Future<void> play(String key, {int? variant}) async {
    if (!enabled) return;
    final String? f = _pick(key, variant);
    if (f == null) return;
    await _playFile(f, key);
  }

  /// 打字机逐字音节（[emotion] 取 persona 的 12 情绪；[soft] = 她的低声/旁白）
  static Future<void> syllable(String emotion, {bool soft = false}) async {
    if (!enabled) return;
    final String e = _emotions.contains(emotion) ? emotion : 'neutral';
    final int n = _rnd.nextInt(4);
    await _playFile('audio/syl_${e}_$n.wav', 'syl:$e', soft: soft);
  }

  // ── 底噪（循环）─────────────────────────────────────────────
  static AudioPlayer? _ambient;
  static bool _ambientOn = false;

  /// 开/关环境底噪（原型 `Sound.ambient(level)`；这里是"在/不在"两态）
  static Future<void> ambient(bool on) async {
    if (!enabled || !on) {
      if (_ambientOn) {
        _ambientOn = false;
        try {
          await _ambient?.stop();
        } catch (_) {}
      }
      return;
    }
    if (_ambientOn) return;
    final List<String>? files = table['ambient'];
    if (files == null || files.isEmpty) return;
    try {
      final AudioPlayer p = _ambient ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(AssetSource(files.first), volume: volume * 0.5);
      _ambientOn = true;
    } catch (e) {
      failCount++;
      lastError = '底噪：$e';
      debugPrint('[sfx] 底噪不可用：$e');
    }
  }

  static Future<void> _playFile(String file, String key, {bool soft = false}) async {
    final _Slot? slot = await _take();
    if (slot == null) return; // 槽位全忙：这一发不播（不是失败，不记账）
    try {
      final AudioPlayer p = await slot.ready;
      // ⚠️ 这里**不再** `stop()`：拿到的一定是空闲槽位。
      //
      // ⚠️⚠️ 真正的坑（独立验收 task-14 找到的真因）：audioplayers 在低延迟
      // 模式下偶发等不到平台 `prepared` 事件，`play()` 会一直挂到
      // `preparationTimeout`（默认 **30s**）才抛（`audioplayer.dart:22/366`）。
      // 一发挂住就占着槽位 30 秒 → 后面几十发全被"全忙丢弃"。
      // 所以这里给 `play()` 配 [_playWatchdog]：超时即**放弃这一发**（记
      // [dropCount]，不算失败、不刷日志），并把坏槽踢出池子换新的——
      // 用一个可诊断的丢弃换掉"一次卡顿拖垮整段逐字音"。
      final Future<void> playing = p.play(
        AssetSource(file),
        volume: volume * (soft ? 0.5 : 1.0),
      );
      if (!await _startedWithin(playing, _playWatchdog)) {
        dropCount++;
        lastDrop = key;
        debugPrint('[sfx] 起播超时（丢弃这一发）key=$key file=$file');
        _retire(slot);
        return;
      }
      _releaseWhenDone(slot, p);
    } catch (e) {
      // 素材缺失 / 平台不支持都只是"没声"：记一行，不抛
      slot.busy = false;
      failCount++;
      lastError = '$key → $e';
      debugPrint('[sfx] 播放失败 key=$key file=$file：$e');
    }
  }

  /// 起播是否在 [timeout] 内成功（超时返回 false；异常照旧往上传）
  static Future<bool> _startedWithin(Future<void> playing, Duration timeout) {
    final Completer<bool> c = Completer<bool>();
    playing.then((_) {
      if (!c.isCompleted) c.complete(true);
    }).catchError((Object e, StackTrace s) {
      if (!c.isCompleted) c.completeError(e, s);
    });
    Timer(timeout, () {
      if (!c.isCompleted) c.complete(false);
    });
    return c.future;
  }

  /// 把坏槽（起播超时的那个实例）踢出池子并销毁；**不 await**，不阻塞这一发
  static void _retire(_Slot slot) {
    slot.busy = true; // 永不复发
    _slots.remove(slot);
    slot.ready
        .then((AudioPlayer p) => p.dispose())
        .catchError((Object _) {})
        .ignore();
  }

  /// 起播后把槽位还回池子。
  ///
  /// 优先听 `onPlayerComplete`（不猜时长），并在释放时**取消订阅**
  /// （完成事件永不到达的槽会累积订阅 → 慢性泄漏，task-14 观察点②）；
  /// SoundPool 低延迟路径不保证回调，所以配一个 [_busyHold] 兜底计时器——
  /// 否则槽位会泄漏成"越用越没声"。
  /// 这两个都只在**起播成功之后**创建，所以 widget 测试里不会留 pending timer。
  static void _releaseWhenDone(_Slot slot, AudioPlayer p) {
    bool released = false;
    StreamSubscription<void>? sub;
    void release() {
      if (released) return;
      released = true;
      sub?.cancel();
      slot.busy = false;
    }

    try {
      sub = p.onPlayerComplete.listen((_) => release());
    } catch (_) {}
    Timer(_busyHold, release);
  }

  /// 释放（App 退出/测试收尾）
  static Future<void> dispose() async {
    for (final _Slot s in _slots) {
      try {
        await (await s.ready).dispose();
      } catch (_) {}
    }
    _slots.clear();
    try {
      await _ambient?.dispose();
    } catch (_) {}
    _ambient = null;
    _ambientOn = false;
  }
}

/// 池里的一个播放器槽位：
/// - [ready]：**配置完成**的播放器（在它 resolve 之前谁都不能用——见 `_take()` 的说明）
/// - [busy]：是否正被一发音效占用（占用期间绝不复用，避免同实例上 stop/play 交错）
class _Slot {
  _Slot(this.ready);
  final Future<AudioPlayer> ready;
  bool busy = false;
}
