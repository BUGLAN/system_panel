/// `set_mainline` —— 「她」在 agent 循环里**立主线**（docs/06 的核心动作）。
///
/// ═══════════════════════════════════════════════════════════
///  为什么是一个工具，而不是另开一条 prompt→JSON 的旁路
/// ═══════════════════════════════════════════════════════════
///  2026-10-12 宿主指出：「我是想要让这个人物作为 agent 的，只是通过对话拆解
///  是不是有问题」。之前的做法（`goal_planner.dart`）是**在对话之外**发一次
///  独立请求、在 prompt 里求 JSON、再手抠平衡括号 —— 那条路不接工具、不接
///  状态、不接记忆，她既看不到宿主的等级/连败/最弱维，也无法自我矫正。
///
///  现在把它变成**工具**：她先 `get_status`（必要时 `recall`），再调用本工具
///  把环链交上来。几处收益：
///    · 结构化输出走 **function calling 的 JSON Schema**（由端点约束生成），
///      不再靠"求它输出 JSON 再解析"——这正是 OpenAI Agents SDK 里
///      `AgentOutputSchema.validate_json` 那套做法，也是官方明确推荐的路子；
///    · 参数不合格时**返回 fail 让她当场重来**（guardrail 在工具执行层），
///      而不是整条静默退回模板；
///    · 她能顺手把 `get_status` 的结论用进拆解里（"你连败 2 次，第一环
///      我给你放到 5 分钟"）。
///
///  ⚠️ **只暂存，不落库**：[MainlineDraft] 收下环链，真正的铸链交给调用方
///     （`buildFirstGoal` / `buildNextGoal`）。这样
///      ① 绑定仪式期还没有 QuestFlow 也能用；
///      ② 她后面几轮万一崩了，不会留下半条已写进存档的主线。
///     难度阶梯（档位/时限上限/单调性/末环）**不在这里收口**，那是
///     `goal_gen` 的规则，工具只保证"形状对"。
library;

import '../data/rarity.dart';
import '../state/goal_gen.dart';
import 'tools.dart';

/// 环链草案 —— 工具把解析好的环放这儿，调用方取走。
class MainlineDraft {
  /// 工具成功交上来的环（形状已校验；阶梯还没收口）。null = 她没交。
  List<RingSpec>? rings;

  /// 她交了几次（诊断用）
  int attempts = 0;
}

/// 立主线工具的 JSON Schema。`ringCount` 写进描述里，让模型知道要几条。
///
/// 注意 `rank` 只给枚举、**不强制她按阶梯**：档位阶梯是规则（`goal_gen` 收口），
/// 她可以按自己的理解给档位，落地时会被校正 —— 但枚举能防止她吐 'X' 这种值。
Map<String, dynamic> setMainlineSchema(int ringCount) => <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'rings': <String, dynamic>{
      'type': 'array',
      'minItems': ringCount,
      'maxItems': ringCount,
      'description':
          '正好 $ringCount 环。从最容易的一环起步（当天必成），难度与耗时逐环递增，'
          '环与环之间要有真实的进阶关系（不是同一件事改时长），'
          '最后一环是一次能证明目标达成的验证动作。只写宿主自己能做的具体动作，'
          '禁止「坚持」「努力」这类空话。',
      'items': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'short': <String, dynamic>{
            'type': 'string',
            'description': '短标签，不超过 4 个字，显示在环上',
          },
          'title': <String, dynamic>{
            'type': 'string',
            'description': '一句话行动，不超过 20 字，写清做什么、做多久',
          },
          'proof': <String, dynamic>{
            'type': 'string',
            'description': '要拍什么当证据（截图/照片/录音），不超过 10 字',
          },
          'minutes': <String, dynamic>{
            'type': 'integer',
            'description': '预计耗时（分钟），5~180',
          },
          'rank': <String, dynamic>{
            'type': 'string',
            'enum': Rarity.ranks,
            'description': '难度档位 F~S（F 最轻、S 最重）',
          },
        },
        'required': <String>['short', 'title', 'proof', 'minutes', 'rank'],
      },
    },
  },
  'required': <String>['rings'],
};

/// 造一个「立这条主线」的工具。
///
/// [goalText] / [ringCount] 一并写进 description，让她知道这次要拆的是哪句话、
/// 要几环（环数由宿主侧规则决定：首目标 3、长链 5~8，见 docs/05/06）。
AgentTool setMainlineTool({
  required String goalText,
  required int ringCount,
  required MainlineDraft draft,
  void Function()? onStaged,
}) {
  return AgentTool(
    name: 'set_mainline',
    description:
        '把宿主的目标「$goalText」拆成 $ringCount 环、交上来当主线。'
        '调用前建议先用 get_status 看他的现状（等级/连败/最弱维），'
        '必要时用 recall 翻一下他以前说过什么。必须正好 $ringCount 环。',
    parameters: setMainlineSchema(ringCount),
    run: (Map<String, dynamic> args) async {
      draft.attempts++;
      final Object? raw = args['rings'];
      if (raw is! List || raw.isEmpty) {
        return ToolOutcome.fail(
          'rings 要是数组，而且正好 $ringCount 环。你这次没给出来，重来。',
        );
      }
      if (raw.length != ringCount) {
        // ⚠️ 条数不对**必须让她重来**，不能截断/补齐 —— 环数决定主线的天数
        //    （docs/05「首目标 3 天 3 环」、docs/06 长链 5~8），不是可以商量的
        //    输出长度。
        return ToolOutcome.fail(
          '主线要正好 $ringCount 环，你给了 ${raw.length} 环。'
          '按 $ringCount 环重排一遍再交。',
        );
      }
      final List<RingSpec> out = <RingSpec>[];
      for (int i = 0; i < raw.length; i++) {
        final Object? item = raw[i];
        if (item is! Map) {
          return ToolOutcome.fail('第 ${i + 1} 环不是对象。重来。');
        }
        final String short = _str(item['short']);
        final String title = _str(item['title']);
        final String proof = _str(item['proof']);
        final String rank = _str(item['rank']).toUpperCase();
        final Object? minutesRaw = item['minutes'];
        final int minutes = minutesRaw is num
            ? minutesRaw.toInt()
            : int.tryParse(_str(minutesRaw)) ?? -1;
        if (short.isEmpty || title.isEmpty || proof.isEmpty) {
          return ToolOutcome.fail(
            '第 ${i + 1} 环的 short / title / proof 有空的。'
            '每一环都要写清「叫什么、做什么、拍什么」。重来。',
          );
        }
        if (!Rarity.ranks.contains(rank)) {
          return ToolOutcome.fail(
            '第 ${i + 1} 环的 rank「${_str(item['rank'])}」不是 F~S。重来。',
          );
        }
        if (minutes <= 0) {
          return ToolOutcome.fail(
            '第 ${i + 1} 环的 minutes 要是正整数（分钟）。重来。',
          );
        }
        out.add(
          RingSpec(
            short: short,
            title: title,
            proof: proof,
            minutes: minutes,
            rank: rank,
          ),
        );
      }
      draft.rings = out;
      onStaged?.call();
      return ToolOutcome.ok(
        '主线收下了：$ringCount 环，'
        '${out.first.short} → … → ${out.last.short}。拿去用一句话告诉他为什么这么排。',
        data: <String, dynamic>{
          'rings': <Map<String, dynamic>>[
            for (final RingSpec r in out)
              <String, dynamic>{
                'short': r.short,
                'title': r.title,
                'proof': r.proof,
                'minutes': r.minutes,
                'rank': r.rank,
              },
          ],
        },
      );
    },
  );
}

String _str(Object? v) => v is String ? v.trim() : (v == null ? '' : '$v');
