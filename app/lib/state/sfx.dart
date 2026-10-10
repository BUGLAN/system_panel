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

  /// 事件 → 素材路径（相对 `assets/`，`AssetSource` 前缀就是 `assets/`）。
  /// 多条 = 变体：每次随机取一条（原型每发都随机音高，不随机就丢手感）。
  /// 命名约定由 `tools/audio/` 的烘焙脚本保证。
  static const Map<String, List<String>> table = <String, List<String>>{
    // ── 高频 12 件（docs/22 R3-A）──
    'tap': <String>['audio/tap.wav'],
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
  static final List<AudioPlayer> _pool = <AudioPlayer>[];
  static int _next = 0;
  static const int _poolSize = 6;

  static Future<AudioPlayer> _take() async {
    if (_pool.length < _poolSize) {
      final AudioPlayer p = AudioPlayer();
      // 短音效用低延迟模式（Android 走 SoundPool），逐字音节才跟得上
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setReleaseMode(ReleaseMode.stop);
      _pool.add(p);
      return p;
    }
    final AudioPlayer p = _pool[_next % _pool.length];
    _next++;
    return p;
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
      debugPrint('[sfx] 底噪不可用：$e');
    }
  }

  static Future<void> _playFile(String file, String key, {bool soft = false}) async {
    try {
      final AudioPlayer p = await _take();
      await p.stop(); // 池内复用前先掐掉上一次
      await p.play(AssetSource(file), volume: volume * (soft ? 0.5 : 1.0));
    } catch (e) {
      // 素材缺失 / 平台不支持都只是"没声"：记一行，不抛
      debugPrint('[sfx] 播放失败 key=$key file=$file：$e');
    }
  }

  /// 释放（App 退出/测试收尾）
  static Future<void> dispose() async {
    for (final AudioPlayer p in _pool) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _pool.clear();
    try {
      await _ambient?.dispose();
    } catch (_) {}
    _ambient = null;
    _ambientOn = false;
  }
}
