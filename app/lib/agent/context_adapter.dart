import '../data/rarity.dart';
import '../state/goal.dart';
import '../state/host_state.dart';
import '../state/quest.dart';
import '../state/quest_flow.dart';
import 'tools.dart';

/// ═══════════════════════════════════════════════════════════
///  AgentContext 的真实适配器（docs/19 §A3）—— 把工具接到 QuestFlow 上
///
///  数据源：`QuestFlow`（队列/接单/结算唯一真源）+ 它持有的 `HostState`/`Goal`。
///  main.dart 用 `flowOf: () => _flow` 传**取流回调**而非实例——绑定/读档会把
///  `_flow` 整个换掉（`QuestFlow.fromSave`），闭包永远读到当前那份。
///
///  变更通知：工具改动队列后回调 [onChanged]，main.dart 接
///  「同步档案副本 + 存档」。换任务走 `QuestFlow.retreat`（D4「换一个」语义：
///  非 F 降一档重刻、F 换一张别的 F、累计 3 次触发「口头巨人」）。
///
///  **安全钳制不变**：适配器不提供经验/金币/等级的任何写入口——数值只能
///  经结算（QuestFlow.settle）入账。执行史落库是后续卡，[recentHistory]
///  暂给空表（summarize_progress 会如实说「空白」，不造假数据）。
/// ═══════════════════════════════════════════════════════════
class QuestFlowAdapter implements AgentContext {
  QuestFlowAdapter({required this.flowOf, this.onChanged});

  /// 取当前 QuestFlow（绑定/读档会换实例，别存引用）
  final QuestFlow Function() flowOf;

  /// 工具改动队列后的通知（main：同步档案副本 + _persist）
  final void Function()? onChanged;

  QuestFlow get _flow => flowOf();

  @override
  Map<String, dynamic> statusSummary() {
    final QuestFlow f = _flow;
    final HostState h = f.host;
    final Goal g = f.goal;
    final MapEntry<String, int> weakest = h.weakest;
    return <String, dynamic>{
      'name': h.name,
      'lv': h.lv,
      'exp': h.exp,
      'expNeed': QuestFlow.needFor(h.lv),
      'coins': h.coins,
      'streak': h.streak,
      'bestStreak': h.bestStreak,
      'queue': f.queue.length,
      'goal': g.text,
      'planDone': g.doneCount,
      'planTotal': g.plan.length,
      'weakest': weakest.key,
      'weakestValue': weakest.value,
      'doneCount': h.doneCount,
      'failCount': h.failCount,
      'items': Map<String, int>.of(h.items),
      'executing': f.active?.task.name ?? '',
    };
  }

  @override
  ToolOutcome swapQuest({String? rank, String? note}) {
    final QuestFlow f = _flow;
    if (f.queueEmpty) {
      return ToolOutcome.fail('队列是空的。没有可换的单。');
    }
    final Quest head = f.head!;
    if (head.kind == 'main') {
      // docs/18 §2.7：主线单不可换——她直接拒绝（原型 store.js:254 语义）
      return ToolOutcome.fail('主线上的单不能换。这是你自己选的目标，要么做完，要么认输重来。');
    }
    // D4「换一个」语义：非 F 降一档重刻（单号不变）；F 级还退=换一张别的 F
    final RetreatOutcome? out = f.retreat(head);
    if (out == null) {
      return ToolOutcome.fail('这张单已经不在她手里了，换不了。');
    }
    final Quest? nt = out.replacement;
    if (nt == null) {
      return ToolOutcome.fail('池子里的 F 级备胎也空了。原单先留着，明天再说。');
    }
    onChanged?.call();
    final String why = (note == null || note.trim().isEmpty) ? '' : '（${note.trim()}）';
    final String shame = out.shame ? '\n——退缩满三次，「口头巨人」给你挂上了。' : '';
    return ToolOutcome.ok(
      '换好了$why。「${nt.name}」现在是 ${nt.rank} 级 · ${nt.minutes} 分钟'
      '（№ ${nt.serial.toString().padLeft(4, '0')}）。$shame',
      data: <String, dynamic>{
        'serial': nt.serial,
        'name': nt.name,
        'rank': nt.rank,
        'minutes': nt.minutes,
        'retreatTotal': out.total,
      },
    );
  }

  @override
  ToolOutcome adjustQuestPlan({
    int? minutes,
    String? rank,
    int? postponeMinutes,
    String? note,
  }) {
    final QuestFlow f = _flow;
    if (f.queueEmpty) {
      return ToolOutcome.fail('队列是空的。没有可调整的单。');
    }
    final Quest head = f.head!;
    if (head.kind == 'main') {
      return ToolOutcome.fail('主线单的规格不动。要改的是你自己，不是目标。');
    }
    int newMinutes = head.minutes;
    if (minutes != null) {
      newMinutes = minutes;
    } else if (postponeMinutes != null) {
      newMinutes = head.minutes + postponeMinutes; // 顺延
    }
    newMinutes = newMinutes.clamp(5, 180).toInt();
    String newRank = head.rank;
    Map<String, int> newAttrs = head.attrs;
    if (rank != null && Rarity.table.containsKey(rank.trim().toUpperCase())) {
      newRank = rank.trim().toUpperCase();
      // 档位变 → 六维按新档点数重分（与 QuestFlow._reRank 同口径）
      newAttrs = QuestFlow.splitAttrs(head.attrs, Rarity.of(newRank).pt);
    }
    f.queue[0] = Quest(
      serial: head.serial,
      kind: head.kind,
      planIndex: head.planIndex,
      planTotal: head.planTotal,
      goalId: head.goalId,
      name: head.name,
      reason: head.reason,
      proof: head.proof,
      minutes: newMinutes,
      rank: newRank,
      attrs: newAttrs,
      hinted: head.hinted,
    );
    // 队列手术后的读数对齐——main 直接做队列手术时同款动作（见 main.dart）
    f.host = f.host.copyWith(queue: f.queue.length);
    onChanged?.call();
    return ToolOutcome.ok(
      '改好了：「${f.queue.first.name}」→ ${f.queue.first.rank} 级 · '
      '${f.queue.first.minutes} 分钟。做得到吧？',
      data: <String, dynamic>{
        'serial': f.queue.first.serial,
        'name': f.queue.first.name,
        'rank': f.queue.first.rank,
        'minutes': f.queue.first.minutes,
      },
    );
  }

  @override
  List<Map<String, dynamic>> recentHistory({int days = 7}) {
    // 执行史落库是后续卡；这里如实给空表（不拿终身计数冒充近 7 天）
    return const <Map<String, dynamic>>[];
  }
}
