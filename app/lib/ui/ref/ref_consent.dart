import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../design/ref.dart';
import 'ref_core.dart';
import 'ref_inputs.dart';
import 'ref_kit.dart';
import 'ref_motion.dart';
import 'ref_text.dart';

/// ═══════════════════════════════════════════════════════════
///  隐私同意页（G2.1）—— 参考稿没有覆盖，按绑定仪式（ref_onboard）的
///  视觉语言补：eyebrow + h1 + 核心/气泡 + 数据去向卡 + 两篇协议入口 + 主键。
///
///  出现时机由主壳决定：开机屏点「唤醒」之后、进绑定仪式或大厅之前；
///  未同意或协议版本变了就先出这一页。撤回同意后也回到这一页。
///
///  为什么「不同意」不退出 App：iOS 不允许程序自己退出（审核会拒），
///  安卓上也没必要——留在本页，让她说清楚「没有这些我没法工作」，
///  宿主想通了随时点【同意并继续】。
///
///  布局纪律：内容区可滚、两颗键钉在底部 —— 320×640 也不溢出；本页没有
///  输入框，与键盘无关。
/// ═══════════════════════════════════════════════════════════

/// 两篇协议：标题 / 眉 / 资源路径集中在这里，同意页与系统设置抽屉共用。
enum LegalDoc {
  agreement('用户协议', 'TERMS · 用户协议', 'assets/legal/user_agreement.md'),
  privacy('隐私政策', 'PRIVACY · 隐私政策', 'assets/legal/privacy_policy.md');

  const LegalDoc(this.title, this.eyebrow, this.asset);

  /// 中文标题（不带书名号）
  final String title;

  /// 全文页顶部的眉
  final String eyebrow;

  /// 正文资源（pubspec 的 `assets/legal/`）
  final String asset;
}

class RefConsent extends StatelessWidget {
  const RefConsent({
    super.key,
    required this.onAgree,
    required this.onDecline,
    required this.onOpenDoc,
    this.declined = false,
    this.renew = false,
  });

  /// 【同意并继续】
  final VoidCallback onAgree;

  /// 「不同意」—— 主壳只记一笔 [declined]，不退出、不跳页
  final VoidCallback onDecline;

  /// 点开《用户协议》/《隐私政策》全文
  final ValueChanged<LegalDoc> onOpenDoc;

  /// 点过「不同意」：她换成「明白，但没法工作」那句
  final bool declined;

  /// 同意过旧版本（协议更新了）：标题与台词改成「重新签」
  final bool renew;

  /// 她的三句台词（`[]` 是打字机的高亮记号）
  static const String lineIntro =
      '拆任务、陪你说话、验证据，都要把内容交给 [AI 服务] 过一遍。'
      '点头之前，先看清楚哪些东西会出门。';
  static const String lineRenew = '协议更新了。规矩改了就得重新签——看一眼，再继续。';
  static const String lineDeclined =
      '明白，不勉强。但没有这些我没法工作：拆不了目标、回不了话、也验不了证据。'
      '想好了随时点 [同意并继续]。';

  String get _line => declined ? lineDeclined : (renew ? lineRenew : lineIntro);

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final bool reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ColoredBox(
      key: const Key('ref.consent'),
      color: Ref.bg,
      child: DecoratedBox(
        // 顶部一团紫雾（与开机屏同一组色），让这一页不是一块死黑
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.1),
            radius: 1.2,
            colors: <Color>[Color(0xFF1A1436), Ref.bg],
          ),
        ),
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                key: const Key('ref.consent.scroll'),
                padding: EdgeInsets.fromLTRB(
                  Ref.gutter,
                  safe.top + Ref.sceneTopNoHud,
                  Ref.gutter,
                  16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    RefReveal(
                      index: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: RefEyebrow(
                          text: renew ? 'PRIVACY · 协议已更新' : 'PRIVACY · 隐私与授权',
                          accent: Ref.cyan,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    RefReveal(
                      index: 1,
                      child: Text(
                        renew ? '规矩改了，\n重新签一下。' : '开工之前，\n先把话说清楚。',
                        style: RefType.h1,
                      ),
                    ),
                    const SizedBox(height: 18),
                    RefReveal(
                      index: 2,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          RefCore(
                            size: 62,
                            accent: declined ? Ref.hot : Ref.cyan,
                            animate: !reduce,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _bubble()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    RefReveal(index: 3, child: _flows()),
                    const SizedBox(height: 16),
                    RefReveal(index: 4, child: _docs()),
                  ],
                ),
              ),
            ),
            // 两颗键钉在底部（不随内容滚走）：主键同意，次键不同意 ——
            // 次键用同尺寸幽灵键而不是一行小字：拒绝要和同意一样好找。
            Padding(
              padding: EdgeInsets.fromLTRB(
                Ref.gutter,
                8,
                Ref.gutter,
                safe.bottom + Ref.sceneBottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  RefButton(
                    key: const Key('ref.consent.agree'),
                    label: '同意并继续',
                    trailingTriangle: true,
                    onTap: onAgree,
                  ),
                  const SizedBox(height: 10),
                  RefButton(
                    key: const Key('ref.consent.decline'),
                    label: '不同意',
                    primary: false,
                    small: true,
                    onTap: onDecline,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 她说的那句（与绑定仪式的气泡同款）
  Widget _bubble() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0x12FFFFFF), Color(0x05FFFFFF)],
        ),
        borderRadius: Ref.bubble,
        border: Border.all(color: declined ? Ref.a(Ref.hot, .35) : Ref.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'SYSTEM · 她说',
            style: refText(
              family: Ref.fm,
              size: 10,
              wght: 700,
              ls: 3,
              color: declined ? Ref.hot : Ref.cyan,
            ),
          ),
          const SizedBox(height: 4),
          RefTypewriter(
            key: const Key('ref.consent.line'),
            text: _line,
            style: refText(
              family: Ref.fc,
              size: 15,
              wght: 500,
              height: 1.6,
              color: Ref.txt,
            ),
          ),
        ],
      ),
    );
  }

  /// 数据去向：哪些会发给 AI 服务、哪些只在本机
  Widget _flows() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x08FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Ref.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _flow('→ AI', Ref.cyan, '目标原文与访谈答案', '发给 AI 服务，拆成任务清单'),
          _flow('→ AI', Ref.cyan, '聊天内容', '发给 AI 服务，生成她的回复'),
          _flow('→ AI', Ref.cyan, '证据照片', '发给 AI 服务，核对是否和任务对得上'),
          _flow('本机', Ref.mint, '存档', '等级、主线、记录都存在这台设备上', last: true),
        ],
      ),
    );
  }

  Widget _flow(
    String tag,
    Color c,
    String title,
    String sub, {
    bool last = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Ref.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 固定宽的去向标签：四行左缘对齐，一眼扫出「哪几样出门」
          Container(
            width: 46,
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(vertical: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Ref.a(c, .10),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Ref.a(c, .45)),
            ),
            child: Text(
              tag,
              maxLines: 1,
              style: refText(
                family: Ref.fm,
                size: 10,
                wght: 700,
                ls: .5,
                height: 1.3,
                color: c,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: RefType.srow.copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(sub, style: RefType.srowSub.copyWith(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 两篇协议入口 + 一句「继续即同意」
  Widget _docs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '点【同意并继续】，即表示你已阅读并同意以下两篇：',
          style: refText(size: 12, wght: 400, height: 1.5, color: Ref.dim),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Ref.line),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: <Widget>[
              _docRow(LegalDoc.agreement),
              _docRow(LegalDoc.privacy, last: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _docRow(LegalDoc doc, {bool last = false}) {
    return GestureDetector(
      key: Key('ref.consent.doc.${doc.name}'),
      behavior: HitTestBehavior.opaque,
      // 与系统设置抽屉的行同一口径：整行可点，按下声在这里出
      onTap: () {
        refPressSound('ui.tap');
        onOpenDoc(doc);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Ref.line)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '《${doc.title}》',
                style: refText(size: 15, wght: 700, color: Ref.acid),
              ),
            ),
            Text('查看全文 ›', style: refText(size: 12, wght: 500, color: Ref.dim)),
          ],
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════
///  协议全文页：简单可滚动文本（不引 markdown 依赖）。
///
///  按行显示：`#` 开头的当标题（级数越深字越小），`- ` / `* ` 当列表项，
///  `【占位】` 开头的用金色标出来（占位稿一眼就能认出，别带着它上架）。
/// ═══════════════════════════════════════════════════════════
class RefLegalPage extends StatefulWidget {
  const RefLegalPage({
    super.key,
    required this.doc,
    required this.onClose,
    this.loader,
  });

  final LegalDoc doc;
  final VoidCallback onClose;

  /// 读正文（默认 rootBundle；测试注入假数据，免得依赖资源打包）
  final Future<String> Function(String asset)? loader;

  @override
  State<RefLegalPage> createState() => _RefLegalPageState();
}

/// 一行正文的形态
enum LegalLineKind { heading, bullet, placeholder, blank, body }

/// 解析后的一行（[level] 只对标题有意义：`#` 的个数）
@immutable
class LegalLine {
  const LegalLine(this.kind, this.text, {this.level = 0});
  final LegalLineKind kind;
  final String text;
  final int level;
}

/// 把协议正文按行拆成 [LegalLine]（纯函数，测试直接调）
List<LegalLine> parseLegalText(String raw) {
  final List<LegalLine> out = <LegalLine>[];
  for (final String line0 in raw.replaceAll('\r\n', '\n').split('\n')) {
    final String line = line0.trimRight();
    final String t = line.trimLeft();
    if (t.isEmpty) {
      // 连续空行只留一个（排版间距由标题自己给）
      if (out.isNotEmpty && out.last.kind != LegalLineKind.blank) {
        out.add(const LegalLine(LegalLineKind.blank, ''));
      }
      continue;
    }
    if (t.startsWith('#')) {
      int level = 0;
      while (level < t.length && t[level] == '#') {
        level++;
      }
      out.add(
        LegalLine(
          LegalLineKind.heading,
          t.substring(level).trim(),
          level: level,
        ),
      );
    } else if (t.startsWith('- ') || t.startsWith('* ')) {
      out.add(LegalLine(LegalLineKind.bullet, t.substring(2).trim()));
    } else if (t.startsWith('【占位】')) {
      out.add(LegalLine(LegalLineKind.placeholder, t));
    } else {
      out.add(LegalLine(LegalLineKind.body, t));
    }
  }
  return out;
}

class _RefLegalPageState extends State<RefLegalPage> {
  late Future<String> _text = _load();

  Future<String> _load() =>
      (widget.loader ?? rootBundle.loadString)(widget.doc.asset);

  @override
  void didUpdateWidget(RefLegalPage old) {
    super.didUpdateWidget(old);
    if (old.doc != widget.doc) _text = _load();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('ref.legal'),
      color: Ref.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            RefReveal(index: 0, base: 0, child: _head()),
            Expanded(
              child: FutureBuilder<String>(
                future: _text,
                builder: (BuildContext context, AsyncSnapshot<String> s) {
                  if (s.hasError) {
                    return _note('正文没读出来（${s.error}）。稍后再试。');
                  }
                  if (!s.hasData) return _note('读取中…');
                  final List<LegalLine> lines = parseLegalText(s.data!);
                  return ListView.builder(
                    key: const Key('ref.legal.body'),
                    padding: const EdgeInsets.fromLTRB(
                      Ref.gutter,
                      4,
                      Ref.gutter,
                      28,
                    ),
                    itemCount: lines.length,
                    itemBuilder: (BuildContext _, int i) =>
                        _line(lines[i], first: i == 0),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _head() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Ref.gutter, 18, 12, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                RefEyebrow(text: widget.doc.eyebrow, accent: Ref.cyan),
                const SizedBox(height: 8),
                Text(
                  '《${widget.doc.title}》',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RefType.h1,
                ),
              ],
            ),
          ),
          RefXButton(
            key: const Key('ref.legal.close'),
            back: true,
            accent: Ref.cyan,
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _note(String s) => Padding(
    padding: const EdgeInsets.all(Ref.gutter),
    child: Text(s, style: RefType.meta),
  );

  Widget _line(LegalLine l, {required bool first}) {
    switch (l.kind) {
      case LegalLineKind.blank:
        return const SizedBox(height: 8);
      case LegalLineKind.heading:
        final bool top = l.level <= 1;
        return Padding(
          padding: EdgeInsets.only(top: first ? 0 : (top ? 14 : 12), bottom: 6),
          child: Text(
            l.text,
            style: refText(
              size: top ? 20 : 16,
              wght: top ? 900 : 700,
              height: 1.4,
              color: top ? Ref.txt : Ref.acid,
            ),
          ),
        );
      case LegalLineKind.placeholder:
        return Text(
          l.text,
          style: refText(size: 14, wght: 700, height: 1.7, color: Ref.gold),
        );
      case LegalLineKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('·  ', style: _body),
              Expanded(child: Text(l.text, style: _body)),
            ],
          ),
        );
      case LegalLineKind.body:
        return Text(l.text, style: _body);
    }
  }

  /// 正文：长文要读得下去，用 86% 的主文本色而不是 dim
  static final TextStyle _body = refText(
    size: 14,
    wght: 400,
    height: 1.7,
    color: Ref.a(Ref.txt, .86),
  );
}
