import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../state/haptics.dart';
import '../state/sfx.dart';
import 'choice_rail.dart';
import 'rail_base.dart';

/// 一个可选回答（原型 `choose([{t, v, main}])`）
class Choice {
  const Choice(this.label, {this.main = false});

  final String label;

  /// 主选项＝青色实心那张
  final bool main;
}

/// 一次确认的**回执**：返回「这一下算不算数」。
///
/// 上层可以拒收（例：`_busy` 演出闸门关着的时候、当前时刻压根不该回应），
/// 拒收时 [Choices] **不锁、不响、也不让领位牌滑出去** —— 宿主再点一次即可。
typedef ChoicePick = bool Function(int index);

/// ═══════════════════════════════════════════════════════════
///  回应 —— 乙 · 铭牌轨（docs/28 §5）
///
///  她说一句，宿主从下面挑一个 —— 不做聊天界面，只做铭牌。
///  形态从「底部竖排堆 2 颗胶囊」换成「横排错位斜切铭牌轨」：
///  领位左对齐到边 + 抬起 + 满亮，其余向右阶梯缩进 + 下沉 + 压暗。
///  **外观与动效全在 [ChoiceRail]**，这里只管语义：
///  锁（**上层收下这一下**才锁死，见 [ChoicePick]）、音效震动、收起。
///
///  ⚠️ 手势 / 吸附 / 断命中在 [RailShell] 里（不在这里再写一套）。
/// ═══════════════════════════════════════════════════════════
class Choices extends StatefulWidget {
  const Choices({
    super.key,
    required this.items,
    this.visible = true,
    this.onPick,
  });

  final List<Choice> items;
  final bool visible;

  /// 领位被点实 → 交给上层；**返回 false = 上层没接这一下**
  /// （演出闸门关着、当前时刻不该回应…），这时整条轨保持原样，可以再点。
  final ChoicePick? onPick;

  @override
  State<Choices> createState() => _ChoicesState();
}

class _ChoicesState extends State<Choices> {
  /// 原型 `choose()` 里的 `let locked = false`：第一颗点下去就锁死，
  /// 后面再点谁都不算（`if (locked) return`）。借它保证
  /// 「选一下 = 一声 choose + 一下 8ms 震」不会因为连点发两次。
  bool _locked = false;

  static String _labels(List<Choice> l) =>
      l.map((Choice c) => c.label).join('\u0000');

  @override
  void didUpdateWidget(covariant Choices old) {
    super.didUpdateWidget(old);
    // 收起来再张开 = 新一问（原型 choose() 每次重建都是新的 locked）
    if (!old.visible && widget.visible) _locked = false;
    if (_labels(old.items) != _labels(widget.items)) _locked = false;
  }

  /// 确认那一下：响一声 + 震一下 + 回调，**且只发生一次**。
  /// 返回是否真的确认了（被锁拦住、或**上层没收**都返回 false）。
  bool _confirm(int i) {
    final ChoicePick? onPick = widget.onPick;
    if (onPick == null || _locked) return false;
    // ⚠️ 顺序是「先问上层收不收，再决定要不要锁死 + 发声」——
    //    2026-10-11 实机死局（宿主原话：「此页面会卡死，没有返回的方法」）：
    //    回前台打招呼那 1~3 秒里 `_busy` 关着闸门，宿主点【……接。】，
    //    上层 `_onChoice` 直接 return；而这里**已经把 `_locked` 锁死**、
    //    领位牌照旧播「确认 → 向左滑出 28px + 淡出」，于是牌没了、
    //    剩下那一张也被 `_locked` 吃掉：失败页再没有任何出路，只能杀进程。
    //    现在「上层没收 = 什么都没发生」：牌不滑走、不响、可以再点。
    _locked = true;
    if (!onPick(i)) {
      _locked = false;
      return false;
    }
    // 选项点击（`ui.js:126`）：`Sound.play('choose'); buzz(8);`
    Sfx.play('choose');
    Haptics.buzz('choose');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bool visible = widget.visible;
    final bool reduce = railReduceMotion(context);
    return Positioned(
      left: kRailMarginX,
      right: kRailMarginX,
      bottom: kRailBottom,
      // 收起来时必须同时断掉命中：由 RailShell 的 IgnorePointer(ignoring: !open)
      // 负责（本仓库真踩过：一颗看不见的按钮替派单板的指纹挨点）。
      child: TweenAnimationBuilder<double>(
        // 收起：整叠向下 28px（500ms 位移，节奏照旧）
        tween: Tween<double>(end: visible ? 0 : 1),
        duration: reduce ? Duration.zero : kRailHideMs,
        curve: kOut,
        builder: (BuildContext _, double h, Widget? child) =>
            Transform.translate(
              offset: Offset(0, kRailHideDy * h),
              child: child,
            ),
        child: AnimatedOpacity(
          // ⚠️ 钥匙挂在收起位移 **里面**：`getRect` 不含渲染对象自己的
          // Transform，挂在外面就量不到「向下 28px」。
          key: const Key('choices'),
          // 300ms 淡出（与旧的节奏一致）
          opacity: visible ? 1 : 0,
          duration: reduce ? Duration.zero : kRailFadeMs,
          child: ChoiceRail(
            items: widget.items,
            visible: visible,
            enabled: widget.onPick != null,
            onConfirm: _confirm,
          ),
        ),
      ),
    );
  }
}
