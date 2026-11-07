import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:ui' show AppLifecycleState;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../design/tokens.dart' show SoundRule;

/// ═══════════════════════════════════════════════════════════
///  音效总线—— 素材是**离线烘好的包**（`tools/audio/` 生成，
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

  /// `flutter test` 里没有音频插件：一碰播放器就报 MissingPluginException、
  /// 把测试判红。打字机现在逐字出声，几乎每个页面测试都会碰到，
  /// 所以在总线这一层直接不出声（flutter test 进程带 FLUTTER_TEST 环境变量）。
  static final bool _underTest =
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

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
    // ── 高频 12 件──
    'tap': <String>['audio/tap.wav'],
    // 戳她（原型 audio.js L130 `poke` 620→990Hz triangle；flows.js L649 播它）
    'poke': <String>['audio/poke.wav'],
    'choose': <String>['audio/choose.wav'],
    'land': <String>['audio/land.wav'], // 委托单落板
    'rung': <String>[
      // 稀有度逐级滚（原型按步进变调 → 烘成 5 档）
      'audio/rung_0.wav',
      'audio/rung_1.wav',
      'audio/rung_2.wav',
      'audio/rung_3.wav',
      'audio/rung_4.wav',
    ],
    'rank': <String>[
      // 稀有度落定：原型按 RARITY.i（F~S = 0~6）变调变重
      'audio/rank_0.wav',
      'audio/rank_1.wav',
      'audio/rank_2.wav',
      'audio/rank_3.wav',
      'audio/rank_4.wav',
      'audio/rank_5.wav',
      'audio/rank_6.wav',
    ],
    'ignite': <String>[
      // 点亮进度带（唤醒时）：原型 `audio.js:88-91` 分三档变调
      'audio/ignite_0.wav',
      'audio/ignite_1.wav',
      'audio/ignite_2.wav',
      'audio/ignite_3.wav',
      'audio/ignite_4.wav',
      'audio/ignite_5.wav',
      'audio/ignite_6.wav',
      'audio/ignite_7.wav',
    ],
    // ── 卡牌专属（v16）────────────────────────────────
    // detent：档位咬合（28ms，与 8ms 震动同量级；rung 是 70ms 给派单板的）
    'detent': <String>[
      'audio/detent_0.wav',
      'audio/detent_1.wav',
      'audio/detent_2.wav',
      'audio/detent_3.wav',
      'audio/detent_4.wav',
    ],
    'stamp': <String>['audio/ref_stamp.wav'], // 落定压印（参考稿 stamp）
    'deal': <String>[
      // 发牌（一次最多 2 声：首张 0 + 末张 4）
      'audio/deal_0.wav',
      'audio/deal_1.wav',
      'audio/deal_2.wav',
      'audio/deal_3.wav',
      'audio/deal_4.wav',
    ],
    'seal': <String>['audio/seal.wav'], // 按满接单 / 提交钤印
    'publish': <String>['audio/ding.wav'], // 发布（原型叫 ding，「只属于派单」）
    'impact': <String>['audio/impact.wav'], // 结算砸印
    'count': <String>[
      // EXP 滚数（原型每 55ms 一发）
      'audio/count_0.wav',
      'audio/count_1.wav',
      'audio/count_2.wav',
    ],
    'crit': <String>['audio/ref_crit.wav'],
    'levelup': <String>['audio/ref_levelup.wav'],
    'fail': <String>['audio/ref_fail.wav'],
    // Bug：`boot.wav` **一直在盘上（85 件里的第 1 件）**，
    // 但 `table` 里从来没有这个 key —— 而 `main.dart` 的唤醒流程每次都在调
    // `Sfx.play('boot')`。于是每次唤醒都是一次**空调用**：`_pick` 返回 null、
    // 静默返回、连 `failCount` 都不加，因此这个漏项从来没被任何统计发现。
    'boot': <String>['audio/ref_boot.wav'],
    // ── 底噪（可循环，设置页可关；原型 audio.js 的 ambient）──
    'ambient': <String>['audio/ambient_loop.wav'],
    // ── 参考稿音效：`宿主养成系统_重设计.html` 的 SFX 逐条烘焙 ──
    // v3 界面全按参考稿重做了，音效也用参考稿这一套。原来这些名字经 [designAlias]
    // 映射到 opus-v2 的「最接近件」（error→结算砸印、swipe→28ms detent…），听感对不上。
    // 同名覆盖：stamp / crit / levelup / fail / boot / hold 也换成参考稿版本。
    'click': <String>['audio/ref_click.wav'],
    'soft': <String>['audio/ref_soft.wav'],
    'hover': <String>['audio/ref_hover.wav'],
    'swipe': <String>['audio/ref_swipe.wav'],
    'whoosh': <String>['audio/ref_whoosh.wav'],
    'type': <String>[
      'audio/ref_type_0.wav',
      'audio/ref_type_1.wav',
      'audio/ref_type_2.wav',
      'audio/ref_type_3.wav',
    ],
    'tick': <String>['audio/ref_tick.wav'],
    'beat': <String>['audio/ref_beat.wav'],
    'success': <String>['audio/ref_success.wav'],
    'error': <String>['audio/ref_error.wav'],
    'coin': <String>['audio/ref_coin.wav'],
    'buy': <String>['audio/ref_buy.wav'],
    'unlock': <String>['audio/ref_unlock.wav'],
    'scan': <String>['audio/ref_scan.wav'],
    // 戳她：variant = min(连戳数, 8)，越戳越尖（参考稿 boop(p)）
    'boop': <String>[
      'audio/ref_boop_0.wav',
      'audio/ref_boop_1.wav',
      'audio/ref_boop_2.wav',
      'audio/ref_boop_3.wav',
      'audio/ref_boop_4.wav',
      'audio/ref_boop_5.wav',
      'audio/ref_boop_6.wav',
      'audio/ref_boop_7.wav',
      'audio/ref_boop_8.wav',
    ],
    // 按住认输：variant = 进度第几个 1/8（参考稿是一条随进度升调的锯齿）
    'hold': <String>[
      'audio/ref_hold_0.wav',
      'audio/ref_hold_1.wav',
      'audio/ref_hold_2.wav',
      'audio/ref_hold_3.wav',
      'audio/ref_hold_4.wav',
      'audio/ref_hold_5.wav',
      'audio/ref_hold_6.wav',
      'audio/ref_hold_7.wav',
    ],
  };

  /// 逐字音节（打字机每个显形字一发）：`syl_<情绪>_<变体>.wav`
  static const List<String> _emotions = <String>[
    'neutral',
    'smug',
    'cold',
    'annoyed',
    'pleased',
    'tsun',
    'joy',
    'proud',
    'surprised',
    'sad',
    'focus',
    'sleep',
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

  /// **长音**的槽位保持时长。
  ///
  /// 原来的 [_busyHold] 是固定 250ms —— 它按「最高频那条路」（逐字音 ~60ms）
  /// 标定的，于是所有 >250ms 的音都被**腰斩**：
  ///   `seal` 1.26s / `impact` 1.29s / `stamp` 0.29s / `boot` 3.65s /
  ///   `levelup` ~1.4s / `rank_6` 1.77s。
  /// 后果不只是「声音被切」：槽位提前标空闲 → 被下一发复用到**正在播的实例**上
  /// → 插件层 `stop()/play()` 交错（正是 `.verify/batch2/` 观测到的 30s 超时那类问题）。
  ///
  /// 修法：按 key 给一个**上界**，与 `onPlayerComplete` 谁先到算谁。
  /// 上界取得比素材时长略长（多 200ms 余量），只影响槽位归还、不影响听感。
  static const Map<String, Duration> _longHold = <String, Duration>{
    "seal": Duration(milliseconds: 1500),
    "impact": Duration(milliseconds: 1500),
    "boot": Duration(milliseconds: 1800),
    "levelup": Duration(milliseconds: 2050),
    "rank": Duration(milliseconds: 1200),
    "stamp": Duration(milliseconds: 650),
    "crit": Duration(milliseconds: 1150),
    "fail": Duration(milliseconds: 1100),
    "publish": Duration(milliseconds: 700),
    // 参考稿件：素材时长 + 200ms 余量
    "whoosh": Duration(milliseconds: 800),
    "success": Duration(milliseconds: 950),
    "error": Duration(milliseconds: 580),
    "coin": Duration(milliseconds: 500),
    "buy": Duration(milliseconds: 680),
    "unlock": Duration(milliseconds: 820),
    "hold": Duration(milliseconds: 480),
  };

  /// 这一发最多占着槽位多久
  static Duration _holdFor(String key) => _longHold[key] ?? _busyHold;

  /// 供测试与诊断：某个 key 的槽位保持时长（的回归点）。
  ///
  /// 为什么要暴露它：`_busyHold` 固定 250ms 曾把 `seal`(1.26s) / `impact`(1.29s)
  /// 腰斩 —— 那是**听不出来**但会引发槽位复用错乱的一类缺陷，必须有钉子。
  @visibleForTesting
  static Duration holdForTest(String key) => _holdFor(key);

  /// 单发起播的看门狗：超过它就认为这一发起不来了（平台 `prepared` 丢了），
  /// 丢弃这一发 + 把槽踢出池子（audioplayers 自己的超时是 30 秒，太长——
  /// 一发挂住会拖垮整段逐字音）。
  static const Duration _playWatchdog = Duration(milliseconds: 1200);

  // ── 音频会话（G1.2：打开 App 不许停掉用户正在听的歌）──────────────
  //
  // audioplayers 6.8 不设上下文时用插件默认值（≈ `AudioContextConfig(focus: gain,
  // respectSilence: false)`）：
  //   - Android：**每次起播**都申请 AUDIOFOCUS_GAIN —— 连低延迟的 SoundPool 路径
  //     也申请（audioplayers_android `WrappedPlayer.play → FocusManager`）。音乐 App
  //     收到的是永久失焦，直接停播；而我们一点按钮就会起播。
  //   - iOS：`.playback` 类别 —— 不理静音键，会话一激活就打断别的 App 的音频。
  // 我们只出按钮声和一层底噪，没资格抢焦点。所以：
  //   - iOS 用 `.ambient`：跟随静音键 / 锁屏静音、与其它 App **混音**（ambient 自带
  //     mixWithOthers；平台接口有断言，ambient 不许再显式加这个选项，所以 options 留空）；
  //   - Android 不申请焦点（`none`）；usage 用 game（走媒体音量，静音模式下照常响，
  //     与一般游戏一致；sonification 类 usage 会走系统音量、在部分机型被静音档吞掉），
  //     contentType 用 sonification（短促音效）。
  // 不用 `AudioContextConfig` 拼：它的 respectSilence 在 Android 上会把 usage
  // 换成 notificationRingtone（走铃声音量），不是我们要的。

  /// 全部播放器共用的音频上下文（池里每个槽位 + 底噪那一个）
  static final AudioContext audioContext = AudioContext(
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
  );

  /// 全局会话只设一次。所有新建播放器的路径都先 await 它：iOS 的会话在**第一次
  /// 起播**时激活，那一刻若还是插件默认的 `.playback`，别人的歌已经被打断了。
  static Future<void>? _session;
  static Future<void> _ensureSession() => _session ??= _applySession();

  static Future<void> _applySession() async {
    try {
      await AudioPlayer.global.setAudioContext(audioContext);
    } catch (e) {
      // 设不上也不能拖垮音效（纪律 1）：照旧出声、退回插件默认行为，记账可诊断
      failCount++;
      lastError = '音频会话：$e';
      debugPrint('[sfx] 音频会话设置失败：$e');
    }
  }

  /// 给单个播放器绑上下文（只在 Android 做）。
  ///
  /// 为什么全局设过了还要逐个设：Android 端的全局上下文只是「**之后**新建的
  /// 播放器」的默认值（插件在 `create` 时 copy 一份），而 `AudioPlayer()` 的
  /// 构造是异步自己去发 create 的，和全局那条消息谁先到平台没有保证 —— 逐个设
  /// 不依赖时序。iOS 没有「播放器级」会话（插件会把逐个设当全局再 apply 一遍
  /// 并打一行日志），全局那一下就够了。
  ///
  /// ⚠️ 必须在 `setPlayerMode` **之前**调：Android 端切模式就会按当时的上下文
  /// 建 SoundPool（`WrappedPlayer.playerMode` → `initPlayer`），晚了就白建一个默认池。
  static Future<void> _bind(AudioPlayer p) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await p.setAudioContext(audioContext);
    } catch (e) {
      // 同 [_applySession]：绑不上照样能响，只是可能又去抢焦点 —— 记账别瞒着
      failCount++;
      lastError = '音频上下文：$e';
      debugPrint('[sfx] 播放器绑音频上下文失败：$e');
    }
  }

  /// 建一个**配置完成**的播放器（短音效用低延迟模式：Android 走 SoundPool，
  /// 打字机逐字 34ms 一发才跟得上）
  static Future<AudioPlayer> _create() async {
    await _ensureSession();
    final AudioPlayer p = AudioPlayer();
    await _bind(p); // 先绑上下文再切模式（见 [_bind] 的 ⚠️）
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

  /// 参考稿 SFX 名（JS L904-929）→ 烘焙音效包里最接近的那一件。
  /// 参考稿的音是 WebAudio 现合成的；这里用同语义的烘焙件顶上，
  /// 保证每个参考稿里出声的时刻在 App 里也出声。
  static const Map<String, String> designAlias = <String, String>{
    'click': 'tap',
    'soft': 'choose',
    'hover': 'detent',
    'swipe': 'detent',
    'whoosh': 'deal',
    'type': 'detent',
    'tick': 'detent',
    'beat': 'impact',
    'success': 'rank',
    'error': 'impact',
    'coin': 'count',
    'buy': 'publish',
    'unlock': 'ignite',
    'boop': 'poke',
    'scan': 'rung',
  };

  /// 按事件名播一下；未知事件静默。
  ///
  /// 参考稿事件名先经 [designAlias] 映射；[variant] 用于**按档位变调**的事件
  /// （目前只有 `rank`：稀有度 F~S = 0~6），传别的 key 无副作用（越界会被 clamp 到列表内）。
  static Future<void> play(String key, {int? variant, double gain = 1}) async {
    if (!enabled || _underTest) return;
    if (!table.containsKey(key)) key = designAlias[key] ?? key;
    final String? f = _pick(key, variant);
    if (f == null) return;
    await _playFile(f, key, gain: gain);
  }

  /// 用户音量档（设置页「界面音量」低/中/高 → AgentSettings.gainOf）
  static double userGain = .75;

  /// 每个 cue 上一次出声的时间（节流用）
  static final Map<String, DateTime> _lastCue = <String, DateTime>{};

  /// 按**触发规则**出声（规则表在 tokens.dart `SoundRule.cues`）。
  ///
  /// 与 [play] 的区别：音量按规则缩放（过程音 soft、落定音满），且同一 cue
  /// 有最小间隔 —— 连点/快速拖牌不会变成机关枪。未登记的 cue 名当作
  /// 普通 key 直接播（不吞声）。
  static Future<void> cue(String name, {int? variant}) async {
    if (!enabled || _underTest) return;
    final SoundRule? r = SoundRule.cues[name];
    if (r == null) return play(name, variant: variant);
    if (r.minGapMs > 0) {
      // ⚠️ 按**素材**节流，不按 cue 名：按钮按下的 click 与它打开的面板的
      //    click 是同一声，几毫秒内连发两次只会听成一声「咔哒」变厚。
      final DateTime now = DateTime.now();
      final DateTime? last = _lastCue[r.key];
      if (last != null && now.difference(last).inMilliseconds < r.minGapMs) {
        return;
      }
      _lastCue[r.key] = now;
    }
    return play(r.key, variant: variant, gain: r.gain);
  }

  /// 打字机逐字音节（[emotion] 取 persona 的 12 情绪；[soft] = 她的低声/旁白）
  static Future<void> syllable(String emotion, {bool soft = false}) async {
    if (!enabled || _underTest) return;
    final String e = _emotions.contains(emotion) ? emotion : 'neutral';
    final int n = _rnd.nextInt(4);
    await _playFile('audio/syl_${e}_$n.wav', 'syl:$e', soft: soft);
  }

  // ── 底噪（循环）─────────────────────────────────────────────
  //
  // 底噪是 App 里唯一的循环音（池里的槽位都是 ReleaseMode.stop，播完即停），
  // 所以「切后台要静音」只需要管它：Android 回桌面后播放器不会自己停，
  // 不管的话底噪会一直在桌面上响（G1.2）。
  //
  // 响不响由三件事共同决定（[ambientShouldPlay]）：
  //   [enabled] 音效总开关 · [_ambientWanted] 业务想要 · [_foreground] 在前台
  static AudioPlayer? _ambient;

  /// 底噪播放器此刻是否在响（平台侧状态的镜像，只由 [_applyAmbient] 改）
  static bool _ambientOn = false;

  /// 业务想不想要底噪（main.dart 按「音效」设置经 [ambient] 写入）
  static bool _ambientWanted = false;

  /// App 是否在前台（main.dart 的生命周期经 [lifecycle] 写入）
  static bool _foreground = true;

  /// 底噪的开 / 停**串行**执行。起播要好几次平台往返（建播放器、绑上下文、
  /// 设循环、play）；若期间来了「切后台」，不串行的话停的那一步会看到
  /// 「还没开」而跳过，起播完成后底噪就在后台响着 —— 正是要修的那个症状。
  static Future<void> _ambientOps = Future<void>.value();

  /// 底噪该不该响：音效总开关开 + 业务想要 + 在前台，缺一不可。
  /// 抽成纯函数是为了能在没有音频插件的 `flutter test` 里钉住判定。
  static bool ambientShouldPlay({
    required bool enabled,
    required bool wanted,
    required bool foreground,
  }) => enabled && wanted && foreground;

  /// 生命周期 → 是否在前台；`null` = 这个状态不改变判断。
  /// - resumed：回到前台
  /// - hidden / paused：看不见了（Flutter 保证切后台依次经过 inactive → hidden → paused）
  /// - detached：没有界面了（Android 按返回键退出 Activity 时引擎可能还活着）
  /// - inactive：来电浮层、下拉控制中心、App 切换器的过渡态 —— 还看得见，
  ///   不为它打断底噪（真切走了随后一定有 hidden）
  static bool? foregroundOf(AppLifecycleState s) => switch (s) {
    AppLifecycleState.resumed => true,
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
    AppLifecycleState.inactive => null,
  };

  static bool _ambientShould() => ambientShouldPlay(
    enabled: enabled,
    wanted: _ambientWanted,
    foreground: _foreground,
  );

  /// 当前状态下底噪该不该响（测试钉 main.dart 的转发用；测试里不碰播放器，
  /// 但「想要 / 前后台」这两份状态照常记账）
  @visibleForTesting
  static bool get ambientShouldPlayNow => _ambientShould();

  /// 开/关环境底噪（原型 `Sound.ambient(level)`；这里是"在/不在"两态）。
  /// 记下的是「想要」：真响不响还看总开关与前后台 —— 后台里改了设置，
  /// 这里只记账不起播，等回前台再按当时的设置决定。
  static Future<void> ambient(bool on) {
    _ambientWanted = on;
    return _syncAmbient();
  }

  /// App 生命周期变化（main.dart `didChangeAppLifecycleState` 转发）：
  /// 切后台停底噪；回前台按**当时的**「音效」设置决定恢复不恢复。
  static Future<void> lifecycle(AppLifecycleState s) {
    final bool? fg = foregroundOf(s);
    if (fg == null || fg == _foreground) return Future<void>.value();
    _foreground = fg;
    return _syncAmbient();
  }

  /// 把底噪对齐到 [_ambientShould]（排进 [_ambientOps] 串行执行，执行时再读最新状态）
  static Future<void> _syncAmbient() {
    if (_underTest) return Future<void>.value(); // 状态照记，播放器不碰
    final Future<void> op = _ambientOps.then((_) => _applyAmbient());
    // 链上只留「不会失败」的尾巴：哪一步意外抛了也不能卡死后面的开 / 停
    _ambientOps = op.catchError((Object _) {});
    return op;
  }

  static Future<void> _applyAmbient() async {
    final bool want = _ambientShould();
    if (want == _ambientOn) return;
    if (!want) {
      _ambientOn = false;
      try {
        await _ambient?.stop();
      } catch (_) {}
      return;
    }
    final List<String>? files = table['ambient'];
    if (files == null || files.isEmpty) return;
    try {
      await _ensureSession();
      AudioPlayer? p = _ambient;
      if (p == null) {
        p = AudioPlayer();
        await _bind(p); // 与池里的槽位同一套上下文：底噪也不抢焦点、也跟静音键
        _ambient = p;
      }
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(AssetSource(files.first), volume: volume * 0.5);
      _ambientOn = true;
    } catch (e) {
      failCount++;
      lastError = '底噪：$e';
      debugPrint('[sfx] 底噪不可用：$e');
    }
  }

  static Future<void> _playFile(
    String file,
    String key, {
    bool soft = false,
    double gain = 1,
  }) async {
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
        volume: (volume * userGain * gain * (soft ? 0.5 : 1.0)).clamp(0.0, 1.0),
      );
      if (!await _startedWithin(playing, _playWatchdog)) {
        dropCount++;
        lastDrop = key;
        debugPrint('[sfx] 起播超时（丢弃这一发）key=$key file=$file');
        _retire(slot);
        return;
      }
      _releaseWhenDone(slot, p, key);
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
    playing
        .then((_) {
          if (!c.isCompleted) c.complete(true);
        })
        .catchError((Object e, StackTrace s) {
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
  static void _releaseWhenDone(_Slot slot, AudioPlayer p, String key) {
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
    // 按 key 给上界：长音（seal/impact/boot…）不再被 250ms 腰斩
    Timer(_holdFor(key), release);
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
