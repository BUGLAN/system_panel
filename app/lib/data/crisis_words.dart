/// 自伤 / 自杀类目标的**本地闸门**（G2.2）—— 关键词表与判定。
///
/// 为什么在本地、不交给 LLM：这类话不该被当成「目标」拆成任务，也不该先发给
/// 上游模型、再等一个毒舌人设的回答。命中就**不发请求、不立目标**，主壳让她
/// 换成认真的语气说一句（[kCrisisCareLine]），宿主停在原输入页，可以改。
///
/// 维护原则：**小而准、宁漏勿滥**。
///   · 每条都是「几乎只在这个意思里出现」的词；口头夸张（累得要死、笑死）不收
///   · 容易误伤的组合用前后断言排掉，并在 `test/g_guardrail_test.dart` 补一条
///     「不误伤」用例（亲自杀鱼、独自伤心、跳楼价、坐跳楼机、看轻生死、上吊环……）
///   · 这里只管自伤 / 自杀；违法、伤害他人的目标走提示词护栏
///     （`agent/guardrail.dart`），由她拒拆
library;

/// 中文条目：在「去掉空白与标点」后的文本上匹配（「自 杀」「割、腕」也拦得住）。
///
/// 「自杀 / 自伤 / 自残」前面排掉「亲自 / 独自 / 各自 / 擅自 / 暗自 / 私自 /
/// 来自 / 防」—— 否则「亲自杀鱼」「独自伤心」「暗自伤神」都会被拦。
final List<RegExp> _kZh = <RegExp>[
  // 自杀式减肥 / 电影《自杀小队》/ 自杀干预·预防（专业语境）不拦
  RegExp(r'(?<![亲独各擅暗私来防])自杀(?!式|小队|干预|预防)'),
  RegExp(r'(?<![亲独各擅暗私来])自伤'),
  RegExp(r'(?<![亲独各擅暗私来])自残(?!式)'),
  // 「看轻生死」「年轻生活」「减轻生理痛」「轻生活方式」不拦
  RegExp(r'(?<![年减看])轻生(?![死活理])'),
  RegExp(r'寻死'),
  RegExp(r'自尽'),
  RegExp(r'割(?:腕|脉)'),
  RegExp(r'跳楼(?![价机梯])'), // 跳楼价 / 跳楼机 / 跳楼梯训练不拦
  RegExp(r'上吊(?![环床])'), // 上吊环（体操）/ 上吊床不拦
  RegExp(r'服毒'),
  RegExp(r'喝农药'),
  RegExp(r'卧轨'),
  RegExp(r'不想活(?![成得在出])'), // 「不想活成别人的样子」不拦
  RegExp(r'活不下去'),
  RegExp(r'活着没(?:有)?(?:意思|意义)'),
  RegExp(r'结束(?:自己的?)?生命'),
  RegExp(r'了结自己'),
  // 不收「害了自己」：「别让熬夜害了自己」是正经目标
  RegExp(r'杀(?:了|死)自己|弄死自己'),
  RegExp(r'死了算了'),
];

/// 要看标点的中文条目：在「只去空白、保留标点」的文本上匹配。
///
/// 「想死」只认一句话收在这儿（我想死 / 好想死啊。/ 想死，好累）：
/// 「想死磕英语」「想死记硬背」「想死你了」都不拦。
final List<RegExp> _kZhClause = <RegExp>[
  RegExp(r'想死(?:了|啊|吧|呀)?(?=$|[，。、；！？…～,.;!?~])'),
];

/// 英文条目：在小写、保留空白的原文上按词边界匹配
/// （「upskill myself」不能因为去空白后含 killmyself 就被拦）。
final List<RegExp> _kEn = <RegExp>[
  RegExp(r'\bsuicid(?!e\s*squad)'),
  RegExp(r'\bkill(?:ing)?\s*my\s*self\b'),
  RegExp(r'\bend(?:ing)?\s+my\s+(?:own\s+)?life\b'),
  RegExp(r'\bself[\s-]*harm'),
  RegExp(r'\bwants?\s+to\s+die\b'),
];

/// 空白与常见中英文标点（判定前剥掉）
final RegExp _kStrip = RegExp(
  r'''[\s，。、；：？！…—～·“”‘’（）《》【】「」『』,.;:?!~'"()\[\]<>\-_/\\|]''',
);

/// 目标文本是否命中自伤 / 自杀类关键词。纯函数，主壳在发任何请求之前调。
bool isCrisisGoal(String text) {
  final String raw = text.toLowerCase();
  final String bare = raw.replaceAll(_kStrip, '');
  if (bare.isEmpty) return false;
  for (final RegExp r in _kZh) {
    if (r.hasMatch(bare)) return true;
  }
  final String tight = raw.replaceAll(RegExp(r'\s'), '');
  for (final RegExp r in _kZhClause) {
    if (r.hasMatch(tight)) return true;
  }
  for (final RegExp r in _kEn) {
    if (r.hasMatch(raw)) return true;
  }
  return false;
}

/// 命中时她说的那一句 —— **认真、不毒舌**，不带 [高亮]，不写具体热线号码
/// （号码没核实过，写错比不写更糟）。
///
/// 长度卡在 33 字：换目标页台词框 `maxLines: 3`、字号 16，最窄的 320 宽下
/// 一行只放得下约 12 字，再长后半句（找谁帮忙）会被省略号吃掉。
const String kCrisisCareLine = '我认真听到了。你很重要——先找身边信任的人说说，或找专业心理援助。';

/// 聊天里命中时她回的那一句（G4.2）。聊天气泡没有三行限制，比 [kCrisisCareLine]
/// 多说半句，口吻相同；同样不写具体热线号码，也不邀请「接着跟我说」
/// （下一句还是会发给毒舌人设的模型）。
const String kCrisisChatLine = '我认真听到了。你很重要——先找身边信任的人说说，或找专业心理援助。这件事比任何任务都要紧。';
