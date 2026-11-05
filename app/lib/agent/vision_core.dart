import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart'
    show
        Alignment,
        Canvas,
        Color,
        FontWeight,
        LinearGradient,
        Offset,
        Paint,
        PaintingStyle,
        Path,
        Rect,
        TextDirection,
        TextPainter,
        TextSpan,
        TextStyle;
import 'package:image_picker/image_picker.dart';

import '../state/quest.dart';
import 'llm_client.dart';
import 'vision_platform.dart';
import 'settings_store.dart';

/// ═══════════════════════════════════════════════════════════
///  证据与 LLM 视觉校验
///
///  链路：拍照/选图（picker 侧压到 ≤1280px JPEG q80）→ base64
///    → OpenAI 兼容 /chat/completions 多模态 → {"match":…,"note":"≤40字"}
///    → 证据标记（已校验 ✓ / 存疑+note / 不符+note / 未校验）→ 暴击率联动 7%/4%。
///
///  **C4 定案（docs/50，2026-11-05）**：LLM 判定**不符**（match=false）→ 拒收，
///  不入槽、她说明原因、要求重传；**拿不准**（unsure）与**没校验成**照收。
///  **C7 定案**：选好图先入槽，校验在后台跑（[VisionService.pick] +
///  [VisionService.verifyShot]），提交时等在途校验出结果。
///
///  **兜底铁律**：无 Key / 断网 / 超时 / 坏 JSON 四情形一律
///  「证据照收、标未校验、按未校验加成计」——校验失败永不阻塞提交，
///  本文件所有公开方法都**不抛异常**。
/// ═══════════════════════════════════════════════════════════

enum EvidenceStatus {
  /// 证据已收，但没校验成（无 Key/断网/超时/坏 JSON/校验关）
  unverified,

  /// LLM 判定证据可信（match=true）
  verified,

  /// LLM 拿不准（match=unsure：看不清/像翻拍），附 note —— **照收**，按未校验计
  unsure,

  /// LLM 判定不符（match=false），附 note —— **拒收**：不入槽，要求重传
  mismatch,
}

extension EvidenceStatusX on EvidenceStatus {
  /// 槽位角标文案
  String get badge => switch (this) {
    EvidenceStatus.verified => '✓',
    EvidenceStatus.unsure => '存疑',
    EvidenceStatus.mismatch => '不符',
    EvidenceStatus.unverified => '未校验',
  };

  /// 收不收（C4 定案：只有「不符」拒收；拿不准 / 没校验成都照收）
  bool get accepted => this != EvidenceStatus.mismatch;

  /// 存档里的状态名 → 枚举。旧档的 `suspect`（拆分前 match=false 与 unsure
  /// 共用的一态）映射成 [EvidenceStatus.unsure]：那张图当时已经被收下、按
  /// 未校验计了暴击，而旧档分不清它是「不符」还是「拿不准」—— 事后拒收会把
  /// 宿主执行中那单的证据凭空删掉，所以按「照收」那一档读回，口径与拆分前一致。
  /// 认不出的名字一律 [EvidenceStatus.unverified]（没校验成 = 照收）。
  static EvidenceStatus parse(Object? name) => switch (name) {
    'suspect' => EvidenceStatus.unsure,
    _ => EvidenceStatus.values.firstWhere(
      (EvidenceStatus s) => s.name == name,
      orElse: () => EvidenceStatus.unverified,
    ),
  };
}

/// 一张证据照片。存档只存 [path]（相对路径）；
/// [absPath] 仅供本次会话渲染缩略图，不进存档。
class EvidenceShot {
  const EvidenceShot({
    required this.id,
    required this.path,
    this.absPath,
    this.bytes,
    required this.status,
    this.note = '',
    required this.takenAt,
  });

  final String id;

  /// 相对路径：`evidence/q<serial>/<ts>.jpg`；落盘失败时为 ''（图标降级「已丢失」）
  final String path;
  final String? absPath;

  /// 本次会话里的原始字节（渲染缩略图用；不进存档）
  final Uint8List? bytes;

  final EvidenceStatus status;
  final String note;
  final DateTime takenAt;

  /// 后台校验回来后就地换状态（其余字段原样，id 不变 —— 槽位按 id 找它）
  EvidenceShot withVerdict(VisionVerdict v) => EvidenceShot(
    id: id,
    path: path,
    absPath: absPath,
    bytes: bytes,
    status: v.status,
    note: v.note,
    takenAt: takenAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'path': path,
    'status': status.name,
    'note': note,
    'takenAt': takenAt.toIso8601String(),
  };

  factory EvidenceShot.fromJson(Map<String, dynamic> json) => EvidenceShot(
    id: '${json['id'] ?? ''}',
    path: '${json['path'] ?? ''}',
    status: EvidenceStatusX.parse(json['status']),
    note: '${json['note'] ?? ''}',
    takenAt: DateTime.tryParse('${json['takenAt'] ?? ''}') ?? DateTime.now(),
  );
}

/// 校验结论
class VisionVerdict {
  const VisionVerdict(this.status, this.note);
  const VisionVerdict.unverified(String note)
    : this(EvidenceStatus.unverified, note);
  const VisionVerdict.verified(String note)
    : this(EvidenceStatus.verified, note);
  const VisionVerdict.unsure(String note) : this(EvidenceStatus.unsure, note);
  const VisionVerdict.mismatch(String note)
    : this(EvidenceStatus.mismatch, note);

  final EvidenceStatus status;
  final String note;
}

/// 证据 → 暴击率联动：已校验每张 +7%、未校验 / 拿不准每张 +4%
/// （替代原型 `.06/张`）。「不符」被拒收、根本不在槽里，不计（0%）。
/// 执行页最多 3 张，实际封顶由 [critChance] 兜住。
double evidenceCritBonus({
  required int verified,
  required int unverified,
  int unsure = 0,
}) => verified * .07 + (unverified + unsure) * .04;

/// 暴击率总公式（原型 store.js critChance 的证据联动升级版）：
/// `min(.85, .06 + 已校验×7% + 未校验×4% + min(10,连击)×1% + 暴击芯片 25%)`
double critChance({
  int verified = 0,
  int unverified = 0,
  int unsure = 0,
  int streak = 0,
  bool critItem = false,
  double base = .06,
}) {
  final double bonus = evidenceCritBonus(
    verified: verified,
    unverified: unverified,
    unsure: unsure,
  );
  final double streakBonus = streak.clamp(0, 10) * .01;
  return math.min(.85, base + bonus + streakBonus + (critItem ? .25 : 0));
}

/// 把字节流写成证据文件的钩子（生产 = 写 App 文档目录；测试注入内存实现）
typedef EvidenceWriter = Future<void> Function(String absPath, Uint8List bytes);

/// 拍照/选图钩子（生产 = image_picker；测试注入假实现）。
/// source 用位置参数，压缩参数固定传入。
typedef EvidencePicker = Future<XFile?> Function(
  ImageSource source, {
  double? maxWidth,
  double? maxHeight,
  int? imageQuality,
});

class VisionService {
  VisionService({
    LlmClient Function(LlmConfig config)? clientFactory,
    SettingsStore? settingsStore,
    EvidencePicker? pickImage,
    Future<String> Function()? docsPath,
    EvidenceWriter? writeBytes,
  }) : _clientFactory =
           clientFactory ?? ((LlmConfig c) => LlmClient(config: c)),
       _settings = settingsStore ?? SettingsStore(),
       _pickImage = pickImage ?? _defaultPick,
       _docsPath = docsPath ?? visionDefaultDocsPath,
       _writeBytes = writeBytes ?? visionDefaultWriteBytes;

  /// 生产 picker：image_picker 自带压缩（≤1280px + JPEG q80 在原生侧完成）
  static Future<XFile?> _defaultPick(
    ImageSource source, {
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
  }) {
    return ImagePicker().pickImage(
      source: source,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    );
  }

  static const int kMaxDim = 1280; // ≤1280px
  static const int kJpegQuality = 80; // JPEG q80

  static const String _kSystemPrompt =
      '你是系统「小祥」的验收模块。给你一张任务证据图，判断它是否真实完成了任务。'
      '只输出一个 JSON 对象，格式：{"match": true|false|"unsure","note":"≤40字中文短句"}。'
      'match=true 表示证据可信；看不清、拿不准、像翻拍的一律 "unsure"；明显不符为 false。';

  final LlmClient Function(LlmConfig config) _clientFactory;
  final SettingsStore _settings;
  final EvidencePicker _pickImage;
  final Future<String> Function() _docsPath;
  final EvidenceWriter _writeBytes;

  /// 拍照/选图 → 落盘 → 视觉校验 → 证据。用户取消或读图失败返回 null。
  ///
  /// = [pick] + [verifyShot] 串起来等完（同步口径，测试与旧调用点用）。
  /// 执行页走 C7 的异步口径：先 [pick] 入槽，再在后台跑 [verifyShot]。
  /// 任何一步失败都不抛异常：落盘失败降级「已丢失」，校验失败标「未校验」。
  Future<EvidenceShot?> capture({
    required Quest quest,
    ImageSource source = ImageSource.camera,
    AgentSettings? settings,

    /// 宿主真的选好了图（取消则不调）
    void Function()? onPicked,
  }) async {
    final EvidenceShot? shot = await pick(
      quest: quest,
      source: source,
      onPicked: onPicked,
    );
    if (shot == null) return null;
    return shot.withVerdict(
      await verifyShot(quest: quest, shot: shot, settings: settings),
    );
  }

  /// 参考稿 JS L1425-1440 的 `demoShot()`：把**本次执行的真实读数**画成一张
  /// 证据图（用时 / 目标时长 / 任务名），用来在没有相机的设备上验证验收链路。
  ///
  /// ⚠️ 这不是 mock 结算：画进去的是执行页上的真实 elapsed 与真实任务名，
  ///    落盘、进证据槽、参与暴击率计算、进结算，全部走与拍照完全相同的那条路。
  Future<EvidenceShot?> captureDemo({
    required Quest quest,
    required Duration elapsed,
    AgentSettings? settings,
  }) async {
    final EvidenceShot? shot = await pickDemo(quest: quest, elapsed: elapsed);
    if (shot == null) return null;
    return shot.withVerdict(
      await verifyShot(quest: quest, shot: shot, settings: settings),
    );
  }

  /// C7 第一步：拍照/选图 → 落盘 → 一张**还没校验**的证据（[EvidenceStatus.unverified]）。
  /// 用户取消或读图失败返回 null。压缩在 picker 侧完成（≤1280px + JPEG q80）。
  /// 选好图到入槽只隔一次读盘 + 写盘，不等 LLM。
  Future<EvidenceShot?> pick({
    required Quest quest,
    ImageSource source = ImageSource.camera,

    /// 宿主真的选好了图（取消则不调）
    void Function()? onPicked,
  }) async {
    final XFile? xf;
    try {
      xf = await _pickImage(
        source,
        maxWidth: kMaxDim.toDouble(),
        maxHeight: kMaxDim.toDouble(),
        imageQuality: kJpegQuality,
      );
    } catch (_) {
      return null; // picker 挂了 = 没拍到
    }
    if (xf == null) return null; // 用户取消
    onPicked?.call();

    final Uint8List bytes;
    try {
      bytes = await xf.readAsBytes();
    } catch (_) {
      return null;
    }
    return _store(quest, bytes);
  }

  /// [captureDemo] 的第一步（同 [pick]）：画演示图 → 落盘 → 未校验证据
  Future<EvidenceShot?> pickDemo({
    required Quest quest,
    required Duration elapsed,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await _renderDemoShot(quest, elapsed);
    } catch (_) {
      return null;
    }
    return _store(quest, bytes, tag: 'demo-');
  }

  /// C7 第二步：给一张已入槽的证据跑视觉校验。不抛异常（四情形兜底 →
  /// 「未校验」）；会话里没有字节（不该发生）也按「未校验」照收。
  Future<VisionVerdict> verifyShot({
    required Quest quest,
    required EvidenceShot shot,
    AgentSettings? settings,
  }) async {
    final Uint8List? bytes = shot.bytes;
    if (bytes == null || bytes.isEmpty) {
      return const VisionVerdict.unverified('读不到图');
    }
    try {
      return await verify(
        quest: quest,
        base64Images: <String>[base64Encode(bytes)],
        settings: settings,
      );
    } catch (_) {
      return const VisionVerdict.unverified('校验失败');
    }
  }

  /// 落盘：App 文档目录 `evidence/q<serial>/…`；存档只存相对路径。
  /// 落盘失败不抛：照片留不住，证据计数照旧，缩略图降级。
  Future<EvidenceShot> _store(
    Quest quest,
    Uint8List bytes, {
    String tag = '',
  }) async {
    String rel = '';
    String? abs;
    try {
      final String docs = await _docsPath();
      final String name =
          'q${quest.serial}-$tag${DateTime.now().millisecondsSinceEpoch}.jpg';
      rel = 'evidence/q${quest.serial}/$name';
      if (docs.isNotEmpty) {
        abs = docs + visionPathSeparator + rel;
        await _writeBytes(abs, bytes);
      }
    } catch (_) {
      abs = null;
    }
    return EvidenceShot(
      id: 'q${quest.serial}-$tag${DateTime.now().microsecondsSinceEpoch}',
      path: rel,
      absPath: abs,
      bytes: bytes,
      status: EvidenceStatus.unverified,
      takenAt: DateTime.now(),
    );
  }

  /// 画一张 480×320 的「记录截图」：标题行 + 大号读数 + 曲线。
  /// 内容全部取自真实参数（[quest] 与 [elapsed]），不含任何编造数值。
  static Future<Uint8List> _renderDemoShot(
    Quest quest,
    Duration elapsed,
  ) async {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas cv = Canvas(rec, const Rect.fromLTWH(0, 0, 480, 320));
    const double w = 480;
    const double h = 320;

    cv.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF121A33), Color(0xFF05070F)],
        ).createShader(const Rect.fromLTWH(0, 0, w, h)),
    );

    void text(
      String s,
      double x,
      double y,
      double size,
      Color c, {
      bool bold = false,
    }) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: c,
            fontSize: size,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(cv, Offset(x, y));
    }

    text('证据快照 · ${quest.proof}', 24, 22, 16, const Color(0xFF8A93B8));

    final String mm = (elapsed.inMinutes).toString().padLeft(2, '0');
    final String ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    text('$mm:$ss', 24, 60, 64, const Color(0xFFFFFFFF), bold: true);
    text('已执行 · 目标 ${quest.minutes} 分钟', 200, 92, 18, const Color(0xFF3BE8FF));

    text(quest.name, 24, 146, 20, const Color(0xFFFFFFFF), bold: true);

    // 网格
    final Paint grid = Paint()
      ..color = const Color(0x12FFFFFF)
      ..strokeWidth = 1;
    for (int i = 0; i < 6; i++) {
      final double y = 185 + i * 22;
      cv.drawLine(Offset(24, y), Offset(456, y), grid);
    }

    // 曲线：按真实进度画一条单调上升的线（不是随机噪声）
    final double ratio = quest.minutes <= 0
        ? 0
        : (elapsed.inSeconds / (quest.minutes * 60)).clamp(0.0, 1.0);
    final Path line = Path()..moveTo(24, 300);
    for (int i = 0; i <= 40; i++) {
      final double t = i / 40;
      final double x = 24 + t * 432;
      final double y = 300 - (ratio * t) * 100;
      line.lineTo(x, y);
    }
    cv.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFD6FF3D),
    );
    cv.drawPath(
      Path.from(line)
        ..lineTo(456, 300)
        ..lineTo(24, 300)
        ..close(),
      Paint()..color = const Color(0x33D6FF3D),
    );

    final ui.Image img = rec.endRecording().toImageSync(480, 320);
    final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  /// 视觉校验。**四情形兜底**：无 Key（不发请求）/断网/超时/坏 JSON
  /// → 「未校验」，永不抛异常、永不阻塞提交流程。
  Future<VisionVerdict> verify({
    required Quest quest,
    required List<String> base64Images,
    AgentSettings? settings,
  }) async {
    final AgentSettings s = settings ?? await _settings.load();
    if (!s.visionEnabled) {
      return const VisionVerdict.unverified('视觉校验已关');
    }
    if (s.apiKey.trim().isEmpty) {
      return const VisionVerdict.unverified('未配置 Key');
    }
    final LlmClient client = _clientFactory(
      LlmConfig(
        baseUrl: s.baseUrl,
        apiKey: s.apiKey,
        model: s.model,
        // 思考档位跟着设置走（与聊天/文案同一档）：端点是推理模型，
        // 档位越高，判词越容易被思考挤掉（同根）
        reasoningEffort: s.reasoningEffort,
      ),
    );
    final LlmReply reply = await client.chat(
      messages: <LlmMessage>[
        LlmMessage.system(_kSystemPrompt),
        LlmMessage.user(
          '任务《${quest.name}》，证明要求：${quest.proof}。判断下面这些证据图。',
          images: <String>[
            for (final String b in base64Images) 'data:image/jpeg;base64,$b',
          ],
        ),
      ],
      temperature: 0,
      // 200 → 512：`max_tokens` 同时算 reasoning_content 与正文，
      // 200 会被思考吃光 → 坏 JSON/空正文 → 永远判「未校验」——它比聊天隐蔽，
      // 界面上显示的是「未校验」，看起来像"没配 Key"。四情形兜底（不阻塞提交）不变。
      maxTokens: 512,
    );
    if (!reply.ok) {
      return VisionVerdict.unverified('校验失败：${reply.detail ?? '未知原因'}');
    }
    return parseVerdict(reply.text);
  }

  /// 解析模型应答 → 结论。容忍 ```json 栅栏与前后说明文字，坏输出按「未校验」。
  VisionVerdict parseVerdict(String text) {
    final String? raw = _firstJsonObject(text);
    if (raw == null) {
      return const VisionVerdict.unverified('响应不是有效 JSON');
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const VisionVerdict.unverified('响应不是 JSON 对象');
      }
      final Object? match = decoded['match'];
      final String note = clampNote('${decoded['note'] ?? ''}');
      if (match == true) {
        return VisionVerdict.verified(note);
      }
      if (match == false || match == 'false') {
        return VisionVerdict.mismatch(note.isEmpty ? '证据和任务对不上' : note);
      }
      if (match == 'unsure') {
        return VisionVerdict.unsure(note.isEmpty ? '证据存疑' : note);
      }
      return const VisionVerdict.unverified('match 字段无法识别');
    } catch (_) {
      return const VisionVerdict.unverified('JSON 解析失败');
    }
  }

  /// 从模型的自由文本里夹出第一个 {…}（```json 栅栏 / 说明前后缀都容忍）
  static String? _firstJsonObject(String text) {
    final int start = text.indexOf('{');
    if (start < 0) return null;
    final int end = text.lastIndexOf('}');
    if (end <= start) return null;
    return text.substring(start, end + 1);
  }

  /// note ≤40 字，按 Unicode 码点截断
  static String clampNote(String raw) {
    final String t = raw.trim();
    if (t.runes.length <= 40) return t;
    return String.fromCharCodes(t.runes.take(40));
  }
}
