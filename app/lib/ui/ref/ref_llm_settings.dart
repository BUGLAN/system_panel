import 'package:flutter/material.dart';

import '../../agent/llm_client.dart';
import '../../agent/settings_store.dart';
import '../../design/ref.dart';
import '../ref/ref_inputs.dart';
import '../ref/ref_kit.dart';

/// ═══════════════════════════════════════════════════════════
///  LLM 设置（参考稿没有这一块 —— 按「补全设计稿缺失组件」要求新增）
///
///  参考稿的设置面板只有四行（音效 / 秘籍 / 彩蛋 / 重置，L837-843）。
///  本组件补的是功能必需的那一组：API Key、Base URL、模型、温度、
///  上下文长度、流式开关、保存、测试连接。
///
///  视觉全部走参考稿语言（RefTextField / RefSwitch / RefSectionHeader /
///  RefButton），不引入第二套外观：
///   · 面板底：.sheet 的 linear-gradient(#1a1630,#0d0b17) + 上沿 1px
///     rgba(255,255,255,.12)（L482）
///   · 行：.srow 的 padding 15 4 + 底部 1px line（L485）
///   · 主按钮：.btn（62 高 / 斜切 13）
///
///  ⚠️ 保存与测试都**不抛异常**：SettingsStore.save 自己吞磁盘错误并广播，
///     LlmClient.ping 把一切失败折叠成 LlmReply.failure。
/// ═══════════════════════════════════════════════════════════
class LlmSettingsPane extends StatefulWidget {
  const LlmSettingsPane({
    super.key,
    required this.initial,
    this.onSaved,
    this.onClose,
  });

  /// 打开时的当前设置（由调用方从 SettingsStore 读好）
  final AgentSettings initial;

  /// 保存成功（已落盘 + 已广播）
  final ValueChanged<AgentSettings>? onSaved;

  final VoidCallback? onClose;

  @override
  State<LlmSettingsPane> createState() => _LlmSettingsPaneState();
}

class _LlmSettingsPaneState extends State<LlmSettingsPane> {
  final SettingsStore _store = SettingsStore();

  late final TextEditingController _base;
  late final TextEditingController _key;
  late final TextEditingController _model;

  late double _temp;
  late int _ctx;
  late bool _stream;
  late bool _vision;

  bool _dirty = false;
  bool _saving = false;
  bool _testing = false;
  bool _saved = false;
  String? _testMsg;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    final AgentSettings s = widget.initial;
    _base = TextEditingController(text: s.baseUrl);
    _key = TextEditingController(text: s.apiKey);
    _model = TextEditingController(text: s.model);
    _temp = s.temperature;
    _ctx = s.contextLen;
    _stream = s.stream;
    _vision = s.visionEnabled;
  }

  @override
  void dispose() {
    _base.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  AgentSettings get _next => widget.initial.copyWith(
    baseUrl: _base.text.trim(),
    apiKey: _key.text.trim(),
    model: _model.text.trim(),
    temperature: _temp,
    contextLen: _ctx,
    stream: _stream,
    visionEnabled: _vision,
  );

  void _touch() {
    if (!mounted) return;
    setState(() {
      _dirty = true;
      _saved = false;
      _testMsg = null;
      _testOk = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _saved = false;
    });
    final AgentSettings s = _next;
    await _store.save(s);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
      _dirty = false;
    });
    widget.onSaved?.call(s);
  }

  Future<void> _test() async {
    if (_testing) return;
    final AgentSettings s = _next;
    if (s.apiKey.trim().isEmpty) {
      setState(() {
        _testOk = false;
        _testMsg = '先填 API Key —— 没 Key 的请求连发都不会发';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testOk = null;
      _testMsg = '正在按当前输入发一条与聊天同形状的请求…';
      _revealResult();
    });
    final LlmConfig config = LlmConfig(
      baseUrl: s.baseUrl,
      apiKey: s.apiKey,
      model: s.model,
      reasoningEffort: s.reasoningEffort,
      temperature: s.temperature,
      contextLen: s.contextLen,
      stream: s.stream,
    );
    final LlmClient client = LlmClient(config: config);
    final LlmReply r = await client.ping();
    client.close();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = r.hasText;
      if (r.hasText) {
        _testMsg = config.modelWasNormalized
            ? '连接成功 · ${config.model} → ${config.normalizedModel}'
            : '连接成功 · ${config.normalizedModel}';
      } else if (r.ok) {
        _testMsg =
            '连上了但没吐字（HTTP 200、正文为空）—— 多半是思考把预算吃光了，'
            '把温度或预算调一下再试';
      } else {
        _testMsg = '失败 · ${_failureText(r.failure, r.detail)}';
      }
    });
    _revealResult();
  }

  final GlobalKey _resultKey = GlobalKey();

  /// 结果框在滚动区下方：出结果就把它滚进视口，否则点了像没反应
  void _revealResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? c = _resultKey.currentContext;
      if (c == null || !mounted) return;
      Scrollable.ensureVisible(
        c,
        duration: const Duration(milliseconds: 420),
        curve: Ref.ease,
        alignment: .9,
      );
    });
  }

  static String _failureText(LlmFailure? kind, String? detail) =>
      switch (kind) {
        LlmFailure.noKey => '未配置 API Key',
        LlmFailure.timeout => detail ?? '请求超时',
        LlmFailure.network => detail ?? '网络不可达',
        LlmFailure.httpError ||
        LlmFailure.badResponse ||
        null => detail ?? '未知原因',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('ref.llmPane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _head(),
        Expanded(
          child: ListView(
            key: const Key('ref.llmScroll'),
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            children: <Widget>[
              const RefSectionHeader(title: '连接 · ENDPOINT', trailing: '01'),
              _field(
                label: 'Base URL',
                hint: LlmConfig.kDefaultBase,
                controller: _base,
                mono: true,
                note: 'OpenAI 兼容端点；带 /v1 或写全 /chat/completions 都可以',
                keyName: 'ref.llm.base',
              ),
              _field(
                label: 'API Key',
                hint: 'sk-…',
                controller: _key,
                obscure: true,
                mono: true,
                note: '只存本机，不上传；请求头 Authorization: Bearer',
                keyName: 'ref.llm.key',
              ),
              _field(
                label: '模型',
                hint: LlmConfig.kDefaultModel,
                controller: _model,
                mono: true,
                note: '别名会在请求前归一（v4.1flash → deepseek-flash）',
                keyName: 'ref.llm.model',
              ),
              const RefSectionHeader(title: '采样 · SAMPLING', trailing: '02'),
              _temperatureRow(),
              _contextRow(),
              _switchRow(
                label: '流式输出',
                sub: '向端点要 stream:true；客户端仍按整包解析后一次性上屏',
                value: _stream,
                keyName: 'ref.llm.stream',
                onChanged: (bool v) {
                  _stream = v;
                  _touch();
                },
              ),
              const SizedBox(height: 10),
              _switchRow(
                label: '证据视觉校验',
                sub: '关掉 = 纯信任模式：证据照收，但一律按「未校验」计暴击加成',
                value: _vision,
                keyName: 'ref.llm.vision',
                onChanged: (bool v) {
                  _vision = v;
                  _touch();
                },
              ),
              const SizedBox(height: 18),
              _testResult(),
              const SizedBox(height: 14),
            ],
          ),
        ),
        _footer(),
      ],
    );
  }

  Widget _head() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 12, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const RefEyebrow(text: 'LLM · 小祥的大脑'),
                const SizedBox(height: 8),
                Text('LLM 设置', style: RefType.h1),
              ],
            ),
          ),
          RefXButton(onTap: widget.onClose, accent: Ref.acid),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    required String keyName,
    bool obscure = false,
    bool mono = false,
    String? note,
  }) {
    return Padding(
      key: Key(keyName),
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: RefType.srow),
          if (note != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(note, style: RefType.srowSub),
          ],
          const SizedBox(height: 8),
          RefTextField(
            controller: controller,
            hint: hint,
            obscure: obscure,
            mono: mono,
            onChanged: (_) => _touch(),
          ),
        ],
      ),
    );
  }

  Widget _temperatureRow() {
    return Padding(
      key: const Key('ref.llm.temp'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('温度', style: RefType.srow),
              const Spacer(),
              Text(
                _temp.toStringAsFixed(1),
                style: refText(
                  family: Ref.fd,
                  size: 18,
                  wght: 700,
                  height: 1,
                  color: Ref.acid,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text('越低越稳、越高越野；台词/聊天默认 0.8，拆解另有 0.3 的调用点覆盖', style: RefType.srowSub),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: Ref.acid,
              inactiveTrackColor: const Color(0x12FFFFFF),
              thumbColor: Ref.acid,
              overlayColor: Ref.a(Ref.acid, .12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: _temp.clamp(0.0, 1.5),
              min: 0,
              max: 1.5,
              divisions: 15,
              onChanged: (double v) {
                setState(() => _temp = (v * 10).round() / 10);
                _touch();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _contextRow() {
    return Padding(
      key: const Key('ref.llm.ctx'),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('上下文长度（max_tokens 上限）', style: RefType.srow),
          const SizedBox(height: 3),
          Text(
            _ctx == 0
                ? '跟随调用点：台词 4k / 工具循环 8k / 拆解 8k'
                : '上限 $_ctx —— 只会钳小、不会顶掉拆解与工具循环的预算',
            style: RefType.srowSub,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int v in AgentSettings.kContextStops)
                _pill(
                  label: v == 0 ? '自动' : '${v ~/ 1024}k',
                  on: _ctx == v,
                  onTap: () {
                    setState(() => _ctx = v);
                    _touch();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? Ref.acid : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? Ref.acid : Ref.line),
        ),
        child: Text(
          label,
          style: refText(
            family: Ref.fm,
            size: 12,
            wght: 600,
            height: 1,
            color: on ? Ref.onAccent : Ref.dim,
          ),
        ),
      ),
    );
  }

  Widget _switchRow({
    required String label,
    required String sub,
    required bool value,
    required String keyName,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      key: Key(keyName),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ref.line)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: RefType.srow),
                const SizedBox(height: 3),
                Text(sub, style: RefType.srowSub),
              ],
            ),
          ),
          const SizedBox(width: 12),
          RefSwitch(on: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _testResult() {
    final String? msg = _testMsg;
    if (msg == null) return const SizedBox.shrink();
    final Color c = _testOk == null ? Ref.dim : (_testOk! ? Ref.acid : Ref.hot);
    return KeyedSubtree(
      key: _resultKey,
      child: Container(
        key: const Key('ref.llm.testResult'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Ref.a(c, .08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Ref.a(c, .4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c,
                boxShadow: <BoxShadow>[BoxShadow(color: c, blurRadius: 10)],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: refText(
                  family: Ref.fc,
                  size: 12.5,
                  wght: 500,
                  height: 1.5,
                  color: Ref.txt,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Ref.line)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: RefButton(
              key: const Key('ref.llm.test'),
              label: _testing ? '测试中…' : '测试连接',
              primary: false,
              small: true,
              animateSheen: false,
              onTap: _testing ? null : _test,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: RefButton(
              key: const Key('ref.llm.save'),
              label: _saving
                  ? '保存中…'
                  : _saved
                  ? '已保存'
                  : (_dirty ? '保存配置 ·' : '保存配置'),
              small: true,
              onTap: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}

/// 读取当前设置并弹出 LLM 设置（供 main.dart / 旧设置页调用）。
///
/// 返回 true = 期间保存过（调用方据此刷新自己的副本）。
Future<bool> showLlmSettings(
  BuildContext context, {
  AgentSettings? initial,
}) async {
  final AgentSettings seed = initial ?? await SettingsStore().load();
  if (!context.mounted) return false;
  bool saved = false;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭 LLM 设置',
    barrierColor: const Color(0xD904030A),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (BuildContext ctx, Animation<double> a, Animation<double> b) {
      return Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430, maxHeight: 780),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0xFF1A1630), Color(0xFF0D0B17)],
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      const _SheetGrab(),
                      Expanded(
                        child: LlmSettingsPane(
                          initial: seed,
                          onSaved: (_) => saved = true,
                          onClose: () => Navigator.of(ctx).maybePop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder:
        (
          BuildContext ctx,
          Animation<double> a,
          Animation<double> sec,
          Widget? child,
        ) {
          final Animation<double> t = CurvedAnimation(
            parent: a,
            curve: Ref.pop,
          );
          return FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .08),
                end: Offset.zero,
              ).animate(t),
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
  );
  return saved;
}

/// .sheet .grab（L483）：44×5 圆条，rgba(255,255,255,.2)
class _SheetGrab extends StatelessWidget {
  const _SheetGrab();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Center(
        child: Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
