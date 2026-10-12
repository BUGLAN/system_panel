/// t3 · 小祥 Agent 核心的全量离线测试（docs/18 §2.5）。
///
/// 纪律：**不打真网**——LLM 用 `_FakeLlm`（实现 copy.dart 的 `CopyLlmGateway`
/// 最小面，真实现归 t9 的 llm_client.dart）；存档用内存版
/// SharedPreferencesAsync；应用状态用 `MockAgentContext`（QuestFlow 按 §3.1 契约
/// mock，真实现归 t2/集成）。
///
/// 对照验收：
///  ① 多轮对话保持人设且能引用先前对话内容（记忆持久化，重启仍在）
///  ② 工具注册表含 查状态/换任务/调整计划 真实架构位，调用可改变应用状态
///  ③ SystemCopyProvider 生成发布/结算/毒舌/追问，LLM 失败回退内置文案
///  ④ 无网/无 Key 全走模板兜底，不崩不卡（零网络等待）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:system_panel/agent/context_adapter.dart';
import 'package:system_panel/agent/copy.dart';
import 'package:system_panel/agent/memory.dart';
import 'package:system_panel/agent/persona.dart';
import 'package:system_panel/agent/tools.dart';
import 'package:system_panel/data/content.dart';
import 'package:system_panel/data/rarity.dart';
import 'package:system_panel/state/goal.dart';
import 'package:system_panel/state/host_state.dart';
import 'package:system_panel/state/quest.dart';
import 'package:system_panel/state/quest_flow.dart';

/// 每个用例一块干净的内存存储（SharedPreferencesAsync 走新平台接口）
void resetStore([Map<String, Object> seed = const <String, Object>{}]) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(Map<String, Object>.from(seed));
}

/// 造一张单（Quest 无默认构造，这里收拢字段）
Quest _q({
  int serial = 77,
  String kind = 'daily',
  String rank = 'D',
  String name = '夜跑 3 公里',
  int minutes = 30,
}) => Quest(
  serial: serial,
  kind: kind,
  // 默认造的是日常单（不缺任何一张计划）→ planIndex = -1
  planIndex: -1,
  planTotal: 0,
  name: name,
  reason: '',
  proof: '跑步 App 截图',
  minutes: minutes,
  rank: rank,
  attrs: const <String, int>{'体': 1},
);

/// copy.dart 的最小 LLM 面 mock（真实现归 t9）
class _FakeLlm implements CopyLlmGateway {
  _FakeLlm({this.configured = true, this.reply, this.throwing = false});

  @override
  final bool configured;

  String? reply;
  bool throwing;
  int calls = 0;
  List<Map<String, dynamic>>? lastMessages;
  double? lastTemperature;
  int? lastMaxTokens;
  Duration? lastTimeout;

  /// 台词链路要求「关掉思考」（`none`）—— 记下来让用例盯住这条策略
  String? lastReasoningEffort;

  @override
  Future<String?> complete({
    required List<Map<String, dynamic>> messages,
    double? temperature,
    int? maxTokens,
    Duration? timeout,
    String? reasoningEffort,
  }) async {
    calls++;
    lastMessages = messages;
    lastTemperature = temperature;
    lastMaxTokens = maxTokens;
    lastTimeout = timeout;
    lastReasoningEffort = reasoningEffort;
    if (throwing) {
      throw StateError('模拟网络炸了');
    }
    return reply;
  }
}

CopyContext _ctx({
  String rank = 'D',
  String name = '夜跑 3 公里',
  int exp = 32,
  int coin = 15,
  String topic = '换任务',
}) => CopyContext.fromState(
  host: HostState.demo.copyWith(failCount: 3),
  goal: Goal.demo(),
  quest: _q(rank: rank, name: name),
  result: null,
  topic: topic,
).copyWith(exp: exp, coin: coin, crit: false, photos: 2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetStore);

  // ═══════════ ① 多轮对话与人设（记忆持久化，重启仍在）═══════════

  group('persona：人设 prompt 与对话装配', () {
    test('系统 prompt：人设首段原文在场，四语气与铁律在场', () {
      final String sys = const Persona().systemPrompt(
        statusLine: 'LV7 · 连击 6',
        memoryDigest: '- 宿主喜欢夜跑',
        scenario: '与宿主自由对话',
      );
      expect(sys, contains('小祥'));
      expect(sys, contains('大小姐'));
      expect(sys, contains('家道中落'));
      expect(sys, contains('毒舌、爱吐槽'));
      expect(sys, contains('永远靠谱'));
      expect(sys, contains('【四种固定语气】'));
      for (final String tone in Persona.tones.keys) {
        expect(sys, contains(tone));
      }
      expect(sys, contains('【表达铁律】'));
      expect(sys, contains('LV7 · 连击 6'));
      expect(sys, contains('- 宿主喜欢夜跑'));
      expect(sys, contains('与宿主自由对话'));
    });

    test('多轮对话：system 每轮在首、历史居中、本轮输入收尾（人设保持的机制）', () {
      final List<Map<String, dynamic>> messages = const Persona()
          .buildConversation(
            userText: '明天还跑吗？',
            history: const <Map<String, dynamic>>[
              <String, dynamic>{'role': 'user', 'content': '我今晚开始夜跑'},
              <String, dynamic>{'role': 'assistant', 'content': '跑一次算什么。坚持一周再来说。'},
            ],
            memoryDigest: '- 宿主说想夜跑减肥',
          );
      expect(messages.first['role'], 'system');
      expect((messages.first['content'] as String), contains('大小姐'));
      expect(messages[messages.length - 1]['role'], 'user');
      expect(messages[messages.length - 1]['content'], '明天还跑吗？');
      expect(messages[1]['content'], '我今晚开始夜跑');
      expect(messages[2]['content'], '跑一次算什么。坚持一周再来说。');
    });

    test('情绪标签解析：已知剥掉、未知回 neutral、无标签原样', () {
      final TaggedReply a = Persona.splitTag('[smug] 哼，算你过关。');
      expect(a.emotion, 'smug');
      expect(a.text, '哼，算你过关。');
      final TaggedReply b = Persona.splitTag('[whatever]看什么看。');
      expect(b.emotion, 'neutral');
      expect(b.text, '看什么看。');
      final TaggedReply c = Persona.splitTag('先把手头那单做完。');
      expect(c.emotion, 'neutral');
      expect(c.text, '先把手头那单做完。');
    });

    test('情绪标签在第二段也要剥掉并取到情绪（docs/22 F-8）', () {
      // ① 真实观察到的形状：第一段没有标签，标签在第二段开头（旧实现直接漏进正文）
      final TaggedReply t = Persona.splitTag(
        '先把它做完。\n[focus] 下一步只做一件：上床。',
      );
      expect(t.text, '先把它做完。\n下一步只做一件：上床。');
      expect(t.text, isNot(contains('[')));
      expect(t.emotion, 'focus'); // 旧实现只认整条行首 → 这里会退化成 neutral
      // ② 两段都带标签：按人设契约「句首用 [情绪] 标注」，取**第一个**为准，
      //    两个标签都从正文剥掉（不允许念给宿主听）
      final TaggedReply both = Persona.splitTag(
        '[neutral] 先把它做完。\n[focus] 下一步。',
      );
      expect(both.text, '先把它做完。\n下一步。');
      expect(both.emotion, 'neutral');
      // ③ 整行只有标签：不留空行；纯标签消息交给上层按「她没说话」处理
      expect(Persona.splitTag('[focus]\n说点正经的。').text, '说点正经的。');
      expect(Persona.splitTag('[focus]').text, '');
    });

    test('★ 记忆持久化：写一条 → 「杀进程重启」（全新 MemoryStore 实例）→ 还在，且注入对话', () async {
      final MemoryStore before = MemoryStore();
      await before.add('宿主说想夜跑减肥', source: MemorySource.chat, weight: 2);
      await before.add('宿主通常 1-2 点睡', source: MemorySource.interview, weight: 2);

      // 重启 = 全新实例读同一个存档 key
      final MemoryStore after = MemoryStore();
      final List<MemoryEntry> all = await after.entries();
      expect(all.map((MemoryEntry e) => e.text), containsAll(<String>[
        '宿主说想夜跑减肥',
        '宿主通常 1-2 点睡',
      ]));

      // 新对话能引用先前内容：digest 注入 system prompt
      final String digest = await after.digest('夜跑');
      expect(digest, contains('夜跑减肥'));
      final String sys = const Persona().systemPrompt(memoryDigest: digest);
      expect(sys, contains('宿主说想夜跑减肥'));
    });

    test('记忆上限 200：满了淘汰权重低且最旧的，高权重里程碑幸存', () async {
      final MemoryStore m = MemoryStore();
      final DateTime base = DateTime(2026, 1, 1);
      for (int i = 0; i < 200; i++) {
        await m.add('闲聊碎片 $i', at: base.add(Duration(minutes: i)));
      }
      await m.add(
        '首胜里程碑：第一周全勤',
        source: MemorySource.milestone,
        weight: 4,
        at: DateTime(2026, 1, 2),
      );
      final List<MemoryEntry> all = await m.entries();
      expect(all.length, MemoryStore.maxEntries);
      expect(
        all.map((MemoryEntry e) => e.text),
        contains('首胜里程碑：第一周全勤'),
      );
      expect(all.map((MemoryEntry e) => e.text), isNot(contains('闲聊碎片 0')));
    });

    test('记忆去重：同文本再记一次只留一条，并刷新时间', () async {
      final MemoryStore m = MemoryStore();
      await m.add('宿主怕水');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await m.add('宿主怕水', weight: 3);
      final List<MemoryEntry> all = await m.entries();
      expect(all.where((MemoryEntry e) => e.text == '宿主怕水').length, 1);
      expect(all.first.weight, 3);
    });

    test('relevant：关键词命中优先，不足用最近条目补，上限 8', () async {
      final MemoryStore m = MemoryStore();
      await m.add('宿主喜欢夜跑');
      for (int i = 0; i < 10; i++) {
        await m.add('无关记录 $i');
      }
      final List<MemoryEntry> rel = await m.relevant('夜跑');
      expect(rel.first.text, '宿主喜欢夜跑');
      expect(rel.length, 8);
      expect((await m.digest('夜跑')).split('\n').length, lessThanOrEqualTo(8));
    });

    test('存档读坏也不崩：坏 JSON 回空表', () async {
      resetStore(<String, Object>{MemoryStore.defaultKey: '{这不是合法 JSON'});
      final MemoryStore m = MemoryStore();
      expect(await m.entries(), isEmpty);
      expect(await m.digest('任意'), '');
    });
  });

  // ═══════════ ② 工具注册表 ═══════════

  group('tools：注册表与六个默认工具', () {
    test('首发六工具：查状态/换任务/调整计划/记住/查记忆/总结，全部注册在位', () {
      final AgentToolRegistry reg = defaultAgentTools(
        context: MockAgentContext(),
        memory: MemoryStore(),
      );
      expect(reg.names, containsAll(<String>[
        'get_status',
        'swap_quest',
        'adjust_plan',
        'remember',
        'recall',
        'summarize_progress',
      ]));
      expect(reg.length, 6);
    });

    test('toOpenAiTools：function calling 形状正确', () {
      final List<Map<String, dynamic>> tools = defaultAgentTools(
        context: MockAgentContext(),
        memory: MemoryStore(),
      ).toOpenAiTools();
      expect(tools.length, 6);
      for (final Map<String, dynamic> t in tools) {
        expect(t['type'], 'function');
        final Map<String, dynamic> f = t['function'] as Map<String, dynamic>;
        expect(f['name'], isA<String>());
        expect((f['description'] as String), isNotEmpty);
        expect(f['parameters'], isA<Map<String, dynamic>>());
      }
      final Map<String, dynamic> remember = tools
          .firstWhere((Map<String, dynamic> t) => (t['function'] as Map<String, dynamic>)['name'] == 'remember');
      expect(
        ((remember['function'] as Map<String, dynamic>)['parameters']
                as Map<String, dynamic>)['required'],
        contains('text'),
      );
    });

    test('get_status：读出档案真实读数（可改变状态的架构位之「读」）', () async {
      final MockAgentContext ctx = MockAgentContext(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[_q()],
      );
      final AgentToolRegistry reg = defaultAgentTools(context: ctx, memory: MemoryStore());
      final ToolOutcome out = await reg.execute('get_status');
      expect(out.ok, isTrue);
      expect(out.message, contains('LV7'));
      expect(out.message, contains('◈340'));
      expect(out.message, contains('连击 6'));
      expect(out.message, contains('「三个月跑完半马」完成 4/8 单'));
      expect(out.data?['weakest'], '魅');
    });

    test('swap_quest：队首日常被换成候选单，onChanged 通知（工具调用改变应用状态）', () async {
      final List<String> actions = <String>[];
      final MockAgentContext ctx = MockAgentContext(
        queue: <Quest>[_q(), _q(serial: 78, name: '晨间拉伸')],
        nextCandidate: () => _q(serial: 88, name: '拉伸 15 分钟', rank: 'E', minutes: 15),
        onChanged: actions.add,
      );
      final AgentToolRegistry reg = defaultAgentTools(context: ctx, memory: MemoryStore());
      final ToolOutcome out = await reg.execute('swap_quest', <String, dynamic>{
        'note': '今天腿疼',
      });
      expect(out.ok, isTrue);
      expect(out.message, contains('拉伸 15 分钟'));
      expect(ctx.queue.first.serial, 88);
      expect(ctx.queue[1].serial, 78); // 其余不动
      expect(actions, contains('swap_quest'));
    });

    test('swap_quest：主线当前那张直接拒绝（docs/18 §2.7 钳制）', () async {
      final MockAgentContext ctx = MockAgentContext(
        queue: <Quest>[Quest.demo],
        nextCandidate: () => _q(),
      );
      final AgentToolRegistry reg = defaultAgentTools(context: ctx, memory: MemoryStore());
      final ToolOutcome out = await reg.execute('swap_quest');
      expect(out.ok, isFalse);
      expect(out.message, contains('主线'));
      expect(ctx.queue.first.serial, 41); // 原单没动
    });

    test('swap_quest：空队列 / 没有候选单都折成可读的拒绝', () async {
      final AgentToolRegistry empty = defaultAgentTools(
        context: MockAgentContext(queue: <Quest>[]),
        memory: MemoryStore(),
      );
      expect((await empty.execute('swap_quest')).ok, isFalse);

      final AgentToolRegistry noCandidate = defaultAgentTools(
        context: MockAgentContext(queue: <Quest>[_q()]),
        memory: MemoryStore(),
      );
      expect((await noCandidate.execute('swap_quest')).ok, isFalse);
    });

    test('adjust_plan：改时限钳制 5~180、降档、顺延都生效', () async {
      final MockAgentContext ctx = MockAgentContext(queue: <Quest>[_q()]);
      final AgentToolRegistry reg = defaultAgentTools(context: ctx, memory: MemoryStore());

      expect(
        (await reg.execute('adjust_plan', <String, dynamic>{'minutes': 300})).ok,
        isTrue,
      );
      expect(ctx.queue.first.minutes, 180); // 上限钳制

      await reg.execute('adjust_plan', <String, dynamic>{'minutes': 1});
      expect(ctx.queue.first.minutes, 5); // 下限钳制

      await reg.execute('adjust_plan', <String, dynamic>{'postponeMinutes': 15});
      expect(ctx.queue.first.minutes, 20); // 5 + 15 顺延

      await reg.execute('adjust_plan', <String, dynamic>{'rank': 'b'});
      expect(ctx.queue.first.rank, 'B');

      await reg.execute('adjust_plan', <String, dynamic>{'rank': '不认识的档'});
      expect(ctx.queue.first.rank, 'B'); // 非法档位保持原样
    });

    test('adjust_plan：主线单拒调', () async {
      final MockAgentContext ctx = MockAgentContext(queue: <Quest>[Quest.demo]);
      final AgentToolRegistry reg = defaultAgentTools(context: ctx, memory: MemoryStore());
      final ToolOutcome out = await reg.execute('adjust_plan', <String, dynamic>{
        'minutes': 10,
      });
      expect(out.ok, isFalse);
      expect(out.message, contains('主线'));
    });

    test('remember/recall：记住的话进长期记忆，可按关键词翻出来', () async {
      final MemoryStore memory = MemoryStore();
      final AgentToolRegistry reg = defaultAgentTools(
        context: MockAgentContext(),
        memory: memory,
      );
      final ToolOutcome out = await reg.execute('remember', <String, dynamic>{
        'text': ' 宿主每周三加班到十点 ',
      });
      expect(out.ok, isTrue);
      expect((await memory.entries()).map((MemoryEntry e) => e.text), contains('宿主每周三加班到十点'));

      expect((await reg.execute('remember', <String, dynamic>{'text': '  '})).ok, isFalse);

      final ToolOutcome recall = await reg.execute('recall', <String, dynamic>{
        'query': '加班',
      });
      expect(recall.ok, isTrue);
      expect(recall.message, contains('宿主每周三加班到十点'));
    });

    test('summarize_progress：聚合近 7 天执行记录', () async {
      final MockAgentContext ctx = MockAgentContext(
        history: <Map<String, dynamic>>[
          <String, dynamic>{
            'at': DateTime.now().subtract(const Duration(days: 1)),
            'name': '夜跑 3 公里',
            'rank': 'D',
            'result': 'done',
            'minutes': 25,
          },
          <String, dynamic>{
            'at': DateTime.now().subtract(const Duration(days: 2)),
            'name': '夜跑 3 公里',
            'rank': 'D',
            'result': 'crit',
            'minutes': 24,
          },
          <String, dynamic>{
            'at': DateTime.now().subtract(const Duration(days: 3)),
            'name': '背 50 个单词',
            'rank': 'E',
            'result': 'fail',
            'minutes': 0,
          },
          // 8 天前的：不在窗口内
          <String, dynamic>{
            'at': DateTime.now().subtract(const Duration(days: 8)),
            'name': '久远记录',
            'rank': 'C',
            'result': 'done',
            'minutes': 60,
          },
        ],
      );
      final AgentToolRegistry reg = defaultAgentTools(context: ctx, memory: MemoryStore());
      final ToolOutcome out = await reg.execute('summarize_progress');
      expect(out.ok, isTrue);
      expect(out.message, contains('执行 3 单'));
      expect(out.message, contains('完成 2'));
      expect(out.message, contains('战败 1'));
      expect(out.message, contains('49 分钟'));
      expect(out.message, contains('夜跑 3 公里'));
    });

    test('★ 安全钳制：全部工具跑一遍，经验/金币/等级一个不动', () async {
      final MockAgentContext ctx = MockAgentContext(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[_q()],
        nextCandidate: () => _q(serial: 88),
      );
      final MemoryStore memory = MemoryStore();
      final AgentToolRegistry reg = defaultAgentTools(context: ctx, memory: memory);
      for (final String name in reg.names) {
        await reg.execute(name, name == 'remember' ? <String, dynamic>{'text': '测试记忆'} : null);
      }
      expect(ctx.host.lv, HostState.demo.lv);
      expect(ctx.host.exp, HostState.demo.exp);
      expect(ctx.host.coins, HostState.demo.coins);
      expect(ctx.host.items, HostState.demo.items);
    });

    test('可扩展：注册自定义工具即被注册表接管；未知/抛异常的工具都折成 fail 回执', () async {
      final AgentToolRegistry reg = defaultAgentTools(
        context: MockAgentContext(),
        memory: MemoryStore(),
      );
      reg.register(
        AgentTool(
          name: 'open_sheet',
          description: '打开宿主档案页（示例：任何页面操作都能注册成工具）',
          parameters: const <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{}},
          run: (Map<String, dynamic> args) async =>
              ToolOutcome.ok('档案页打开了。', data: args),
        ),
      );
      expect(reg.contains('open_sheet'), isTrue);
      expect(reg.length, 7);
      final ToolOutcome out = await reg.execute('open_sheet', <String, dynamic>{'tab': 'attrs'});
      expect(out.ok, isTrue);
      expect(out.data?['tab'], 'attrs');

      expect((await reg.execute('不存在的工具')).ok, isFalse);

      reg.register(
        AgentTool(
          name: 'boom',
          description: '内部抛异常的工具',
          parameters: const <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{}},
          run: (Map<String, dynamic> args) async => throw StateError('炸了'),
        ),
      );
      final ToolOutcome bad = await reg.execute('boom');
      expect(bad.ok, isFalse);
      expect(bad.message, contains('boom'));
    });
  });

  // ═══════════ ③ SystemCopyProvider ═══════════

  group('copy：SystemCopyProvider 四入口与逐字回退', () {
    test('无 LLM：四入口全部出内置模板，占位符零残留', () async {
      final SystemCopyProvider p = SystemCopyProvider();
      final CopyContext ctx = _ctx();
      for (final CopyLine line in <CopyLine>[
        await p.dispatchLine(ctx),
        await p.settleLine(ctx),
        await p.roastLine(ctx),
        await p.probeLine(ctx),
      ]) {
        expect(line.source, CopySource.template);
        expect(line.text, isNotEmpty);
        expect(line.text.length, lessThanOrEqualTo(SystemCopyProvider.maxChars));
        expect(RegExp(r'\{[a-z]+\}').firstMatch(line.text), isNull);
      }
    });

    test('LINES 逐字保留：发布含 holding 原句、追问含 askGoal 原句、毒舌含补救原句', () {
      // 池内直接引用 LINES 常量——逐字由构造保证，不存在抄写漂移
      expect(SystemCopyTemplates.dispatch, contains(LINES.holding));
      expect(SystemCopyTemplates.probe, contains(LINES.askGoal));
      expect(SystemCopyTemplates.roast, contains(LINES.remedyLine));
      expect(LINES.holding, contains('[[{n}]]'));
      expect(LINES.askGoal, contains('[[一句话]]'));
    });

    test('结算档位映射与各档情绪（F/E→low，D/C→mid，B/A→high，S→top）', () async {
      expect(SystemCopyProvider.tierOf('F'), SettleTier.low);
      expect(SystemCopyProvider.tierOf('e'), SettleTier.low);
      expect(SystemCopyProvider.tierOf('D'), SettleTier.mid);
      expect(SystemCopyProvider.tierOf('C'), SettleTier.mid);
      expect(SystemCopyProvider.tierOf('B'), SettleTier.high);
      expect(SystemCopyProvider.tierOf('A'), SettleTier.high);
      expect(SystemCopyProvider.tierOf('S'), SettleTier.top);
      expect(SystemCopyProvider.tierOf('乱写的'), SettleTier.low);

      final SystemCopyProvider p = SystemCopyProvider();
      expect((await p.settleLine(_ctx(rank: 'E'))).emotion, 'cold');
      expect((await p.settleLine(_ctx(rank: 'D'))).emotion, 'pleased');
      expect((await p.settleLine(_ctx(rank: 'B'))).emotion, 'smug');
      expect((await p.settleLine(_ctx(rank: 'S'))).emotion, 'proud');
      // top 池两句话都带真实结算数字（10 EXP / 20◈ / 6 连击）——渲染必居其一
      final CopyLine top = await p.settleLine(_ctx(rank: 'S', exp: 10, coin: 20));
      const String withLoot = 'S 级都让你啃下来了。……有点东西。[[10]] EXP、◈[[20]]，拿好。';
      const String withStreak = '这一单我记进档案了。[[6]] 连击，就是你现在的名字。';
      expect(top.text == withLoot || top.text == withStreak, isTrue);
    });

    test('毒舌引用真实数据：连败数、最好连击、手里单数都进现场事实', () async {
      final _FakeLlm llm = _FakeLlm(reply: '[annoyed]数据都记着呢。');
      final SystemCopyProvider p = SystemCopyProvider(llm: llm);
      await p.roastLine(_ctx(), reason: '证据一张没交');
      final List<Map<String, dynamic>> msgs = llm.lastMessages!;
      final String brief = msgs.last['content'] as String;
      expect(brief, contains('连败 3 次'));
      expect(brief, contains('连击 6'));
      expect(brief, contains('最好 6'));
      expect(brief, contains('手里 4 单'));
      expect(brief, contains('证据一张没交'));
      expect(msgs.first['content'], contains('大小姐')); // 人设随行
    });

    test('相关记忆随 LLM 请求注入（docs/18 §2.5：上下文含相关记忆）', () async {
      final MemoryStore memory = MemoryStore();
      await memory.add('宿主怕水，泳卡一直吃灰');
      final _FakeLlm llm = _FakeLlm(reply: '[cold]哦。');
      final SystemCopyProvider p = SystemCopyProvider(llm: llm, memory: memory);
      await p.probeLine(_ctx(topic: '游泳'));
      expect(
        (llm.lastMessages!.first['content'] as String),
        contains('宿主怕水，泳卡一直吃灰'),
      );
    });

    test('LLM 成功：剥情绪标签、采用生成文案；temperature/maxTokens/timeout 传递正确', () async {
      final _FakeLlm llm = _FakeLlm(reply: '[smug]行吧，这单算你过关。明天继续。');
      final SystemCopyProvider p = SystemCopyProvider(llm: llm);
      final CopyLine line = await p.dispatchLine(_ctx());
      expect(line.source, CopySource.llm);
      expect(line.emotion, 'smug');
      expect(line.text, '行吧，这单算你过关。明天继续。');
      expect(llm.lastTemperature, 0.8);
      // 台词链路：预算给足 + **档位跟随设置页**（不再硬编码关思考）。
      // 历史是 120 → 512，都是「拿一个小 max_tokens 硬扛思考」；宿主
      // 2026-10-12 定调不用为省 token 做取舍，于是给足 + 保留抬预算兜底网。
      expect(llm.lastMaxTokens, kLineMaxTokens);
      expect(llm.lastReasoningEffort, isNull, reason: '不覆盖 = 用设置页的档位');
      expect(llm.lastTimeout, p.llmTimeout);
      expect(llm.lastMessages!.first['role'], 'system');
    });

    test('LLM 300 字符钳制（docs/18 §2.5）', () async {
      final StringBuffer long = StringBuffer('[cold]');
      for (int i = 0; i < 320; i++) {
        long.write('啰');
      }
      final SystemCopyProvider p = SystemCopyProvider(llm: _FakeLlm(reply: long.toString()));
      final CopyLine line = await p.roastLine(_ctx());
      expect(line.text.length, SystemCopyProvider.maxChars);
    });

    test('兜底铁律：LLM 返回 null/空串/纯标签/抛异常，全部逐字回退内置模板且不抛', () async {
      final CopyContext ctx = _ctx();
      for (final String? reply in <String?>[null, '', '[smug]', '   ']) {
        final SystemCopyProvider p = SystemCopyProvider(llm: _FakeLlm(reply: reply));
        final CopyLine line = await p.settleLine(ctx);
        expect(line.source, CopySource.template);
        expect(line.text, isNotEmpty);
      }
      final SystemCopyProvider throwing = SystemCopyProvider(
        llm: _FakeLlm(throwing: true),
      );
      final CopyLine line = await throwing.roastLine(ctx);
      expect(line.source, CopySource.template);
      expect(line.text, isNotEmpty);
    });
  });

  // ═══════════ ④ 无网/无 Key 兜底冒烟 ═══════════

  group('兜底冒烟：无 Key 零网络等待，全链路不崩', () {
    test('未配置 Key：网关一次都不被调（零等待），文案全走模板', () async {
      final _FakeLlm llm = _FakeLlm(configured: false, reply: '不该被用到');
      final SystemCopyProvider p = SystemCopyProvider(llm: llm);
      final CopyContext ctx = _ctx();
      expect((await p.dispatchLine(ctx)).source, CopySource.template);
      expect((await p.settleLine(ctx)).source, CopySource.template);
      expect((await p.roastLine(ctx)).source, CopySource.template);
      expect((await p.probeLine(ctx)).source, CopySource.template);
      expect(llm.calls, 0);
    });

    test('无 Key 下工具直调照常可用（快捷 chip 场景）', () async {
      final MockAgentContext ctx = MockAgentContext(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[_q()],
        nextCandidate: () => _q(serial: 88, name: '拉伸 15 分钟'),
      );
      final AgentToolRegistry reg = defaultAgentTools(
        context: ctx,
        memory: MemoryStore(),
      );
      final ToolOutcome swap = await reg.execute('swap_quest');
      expect(swap.ok, isTrue);
      expect(ctx.queue.first.name, '拉伸 15 分钟');
      expect((await reg.execute('get_status')).ok, isTrue);
    });
  });

  // ═══════════ ⑤ QuestFlowAdapter（docs/19 §A3 真实适配器）═══════════

  group('QuestFlowAdapter：QuestFlow 数据源的真实 AgentContext', () {
    QuestFlowAdapter adapterOf(
      QuestFlow flow, {
      void Function()? onChanged,
    }) => QuestFlowAdapter(flowOf: () => flow, onChanged: onChanged);

    test('statusSummary：读的是 QuestFlow 真实档案/队列/主线进度', () {
      final QuestFlow f = QuestFlow.demo();
      final Map<String, dynamic> s = adapterOf(f).statusSummary();
      expect(s['lv'], 7);
      expect(s['coins'], 340);
      expect(s['expNeed'], QuestFlow.needFor(7));
      expect(s['queue'], 4); // Quest.demo 主线 + 3 日常
      expect(s['goal'], '三个月跑完半马');
      expect(s['planDone'], 4);
      expect(s['planTotal'], 8);
      expect(s['weakest'], '魅');
    });

    test('flowOf 闭包：_flow 被换实例（绑定/读档）后适配器读到新流', () {
      QuestFlow f = QuestFlow.demo();
      final QuestFlowAdapter a = QuestFlowAdapter(flowOf: () => f);
      expect(a.statusSummary()['queue'], 4);
      f = QuestFlow(
        host: HostState.empty,
        goal: Goal.empty(),
        queue: <Quest>[_q()],
      );
      expect(a.statusSummary()['queue'], 1);
      expect(a.statusSummary()['lv'], 1);
    });

    test('swap_quest：主线当前那张直接拒绝（docs/18 §2.7 钳制在真实流上保持）', () {
      final QuestFlow f = QuestFlow.demo(); // 队首 = Quest.demo（C 级主线）
      final ToolOutcome out = adapterOf(f).swapQuest();
      expect(out.ok, isFalse);
      expect(out.message, contains('主线'));
      expect(f.head!.serial, 41); // 原单没动
      expect(f.retreatTotal, 0); // 拒绝不计退缩
    });

    test('swap_quest：非 F 日常降一档重刻（D4 换一个语义），单号不变', () {
      final QuestFlow f = QuestFlow(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[_q(rank: 'D', minutes: 30)],
      );
      int notified = 0;
      final ToolOutcome out = adapterOf(f, onChanged: () => notified++).swapQuest(
        note: '腿疼',
      );
      expect(out.ok, isTrue);
      expect(out.message, contains('换好了'));
      expect(out.message, contains('腿疼'));
      expect(f.queue.first.rank, 'E'); // D → E 降一档
      expect(f.queue.first.serial, 77); // 单号不变（同一张单刻薄了一点）
      expect(f.retreatToday, 1);
      expect(f.host.queue, 1); // 读数对齐
      expect(notified, 1);
    });

    test('swap_quest：F 级还退 = 换一张别的 F（池子里来）', () {
      final QuestFlow f = QuestFlow(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[_q(rank: 'F', name: '原 F 单')],
      );
      final ToolOutcome out = adapterOf(f).swapQuest();
      expect(out.ok, isTrue);
      expect(f.queue.first.rank, 'F');
      expect(f.queue.first.serial, isNot(77)); // 换成了新单号
    });

    test('adjust_plan：时限钳制 5~180、顺延、降档（六维按新档点数重分）', () {
      final QuestFlow f = QuestFlow(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[_q(rank: 'D', minutes: 30)],
      );
      final QuestFlowAdapter a = adapterOf(f);

      expect(a.adjustQuestPlan(minutes: 300).ok, isTrue);
      expect(f.queue.first.minutes, 180); // 上限钳制

      a.adjustQuestPlan(minutes: 1);
      expect(f.queue.first.minutes, 5); // 下限钳制

      a.adjustQuestPlan(postponeMinutes: 15);
      expect(f.queue.first.minutes, 20); // 顺延 5+15

      a.adjustQuestPlan(rank: 'b');
      expect(f.queue.first.rank, 'B');
      // 六维点数随档位重分：总和 == 新档 pt
      final int sum = f.queue.first.attrs.values.fold(0, (int a, int b) => a + b);
      expect(sum, Rarity.of('B').pt);

      a.adjustQuestPlan(rank: '不认识的档');
      expect(f.queue.first.rank, 'B'); // 非法档位保持原样

      expect(f.host.queue, 1); // 每次手术后读数都对齐
    });

    test('adjust_plan：主线单拒调；空队列拒绝', () {
      final QuestFlow withMain = QuestFlow.demo();
      final ToolOutcome main = adapterOf(withMain).adjustQuestPlan(minutes: 10);
      expect(main.ok, isFalse);
      expect(main.message, contains('主线'));

      final QuestFlow empty = QuestFlow(host: HostState.demo, goal: Goal.demo());
      expect(adapterOf(empty).adjustQuestPlan(minutes: 10).ok, isFalse);
      expect(adapterOf(empty).swapQuest().ok, isFalse);
    });

    test('★ 安全钳制（真实流）：换任务/调整计划跑完，经验/金币/等级/道具一个不动', () {
      final QuestFlow f = QuestFlow(
        host: HostState.demo,
        goal: Goal.demo(),
        queue: <Quest>[_q()],
      );
      final QuestFlowAdapter a = adapterOf(f);
      a.swapQuest();
      a.adjustQuestPlan(minutes: 99, rank: 'E');
      expect(f.host.lv, HostState.demo.lv);
      expect(f.host.exp, HostState.demo.exp);
      expect(f.host.coins, HostState.demo.coins);
      expect(f.host.items, HostState.demo.items);
    });

    test('recentHistory：执行史未落库，如实给空表（不拿终身计数冒充）', () {
      final QuestFlow f = QuestFlow.demo();
      expect(adapterOf(f).recentHistory(), isEmpty);
    });
  });
}
