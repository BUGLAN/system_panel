import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'agent_bridge_store.dart';

/// ═══════════════════════════════════════════════════════════
///  AgentBridge —— 让 Flutter 界面「可被 Agent 看见」
///
///  背景：uiautomator dump 在 Flutter 上几乎读不到东西（实测只有 31 个
///  View 节点、0 个 resource-id），Agent 只能靠 OCR 兜底。本文件提供四条通道：
///
///    1. 语义树（Semantics）—— 全局开启，dump_hierarchy 能读到中文标签
///    2. 节点标记（AgentTag）—— 给关键 UI 打 agent:<id> 标签
///    3. 组件树导出（dumpTree）—— 输出 Widget 树 JSON，含类型/尺寸/位置
///    4. 截图（screenshot）—— 写 PNG 到 /sdcard/agent/
///
///  ⚠️ 全部只在 debug 或 --dart-define=AGENT_BRIDGE=true 时启用，
///     release 包零影响（见 [kAgentBridgeEnabled]）。
/// ═══════════════════════════════════════════════════════════

/// 是否启用 Agent 桥接。
///
/// 默认：debug 构建开，release 关。
/// 可在 release 用 --dart-define=AGENT_BRIDGE=true 强制打开。
const bool kAgentBridgeEnabled = bool.fromEnvironment(
  'AGENT_BRIDGE',
  defaultValue: kDebugMode,
);

/// 关键节点标记：把 [id] 写进 Semantics label，Agent 可用
/// uiautomator dump 或 uiscan.py 直接检索 `agent:<id>`。
///
/// 用法：
/// ```dart
/// AgentTag(
///   id: 'main.close',
///   label: '关闭主线',
///   child: IconButton(...),
/// )
/// ```
///
/// 不开桥接时原样返回 child，不产生任何额外节点。
class AgentTag extends StatelessWidget {
  const AgentTag({
    super.key,
    required this.id,
    required this.child,
    this.label,
    this.button = false,
    this.role,
  });

  /// 稳定标识，建议用 模块.元素 形式（如 main.close / dock.task）。
  final String id;

  /// 给读屏器 / Agent 的可读名称；为空时只用 id。
  final String? label;

  /// 是否是可点元素（映射到 Semantics.button）。
  final bool button;

  /// 可选角色描述（写进 label 前缀，如「按钮」「卡片」）。
  final String? role;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kAgentBridgeEnabled) return child;

    final String tag = (label == null || label!.isEmpty)
        ? 'agent:$id'
        : 'agent:$id ${label!}';
    final String composed = role == null ? tag : '${role!} · $tag';

    return Semantics(
      container: true,
      button: button,
      label: composed,
      child: child,
    );
  }
}

/// 组件树快照：一个节点的精简描述。
@immutable
class AgentNode {
  const AgentNode({
    required this.type,
    required this.depth,
    this.key,
    this.text,
    this.rect,
  });

  final String type;
  final int depth;
  final String? key;
  final String? text;
  final Rect? rect;
}

/// Agent 桥接主入口。
class AgentBridge {
  const AgentBridge._();

  /// 是否启用（供外部判断，避免无谓开销）。
  static bool get enabled => kAgentBridgeEnabled;

  /// 语义树句柄。
  ///
  /// ⚠️ 必须**持有** `ensureSemantics()` 的返回值，否则它会被 GC 回收、
  /// 语义树随之关闭（Flutter 的经典坑）。
  static SemanticsHandle? _semanticsHandle;

  /// 全局语义树开关。
  ///
  /// Flutter 默认只在有 Semantics 组件时才建语义树；打开这个开关后
  /// uiautomator dump 能读到全部带 label 的节点。
  ///
  /// 应在 runApp 之后调用（见 main.dart）。
  static void enableSemantics() {
    if (!kAgentBridgeEnabled) return;
    if (_semanticsHandle != null) return;
    _semanticsHandle = WidgetsBinding.instance.ensureSemantics();
    debugPrint('[AgentBridge] semantics enabled');
    _registerInput();
  }

  static bool _inputOn = false;

  /// 输入注入通道（VM service 扩展）：模拟器的 HID 注入在部分 runtime 上
  /// 进不了 Flutter，Agent 走 `ext.agent.tap / ext.agent.drag` 直接喂
  /// PointerEvent。坐标是逻辑像素。仅 debug / AGENT_BRIDGE 构建存在。
  static void _registerInput() {
    if (_inputOn) return;
    _inputOn = true;
    int pointer = 9000;
    Future<void> send(List<Offset> path, int stepMs) async {
      final int id = pointer++;
      final GestureBinding g = GestureBinding.instance;
      Duration ts = Duration(
        microseconds: DateTime.now().microsecondsSinceEpoch,
      );
      g.handlePointerEvent(
        PointerAddedEvent(pointer: id, position: path.first, timeStamp: ts),
      );
      g.handlePointerEvent(
        PointerDownEvent(pointer: id, position: path.first, timeStamp: ts),
      );
      for (int i = 1; i < path.length; i++) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
        ts += Duration(milliseconds: stepMs);
        g.handlePointerEvent(
          PointerMoveEvent(
            pointer: id,
            position: path[i],
            delta: path[i] - path[i - 1],
            timeStamp: ts,
          ),
        );
      }
      await Future<void>.delayed(Duration(milliseconds: stepMs));
      ts += Duration(milliseconds: stepMs);
      g.handlePointerEvent(
        PointerUpEvent(pointer: id, position: path.last, timeStamp: ts),
      );
      g.handlePointerEvent(
        PointerRemovedEvent(pointer: id, position: path.last, timeStamp: ts),
      );
    }

    double num(Map<String, String> p, String k, [double d = 0]) =>
        double.tryParse(p[k] ?? '') ?? d;

    developer.registerExtension('ext.agent.tap', (
      String _,
      Map<String, String> p,
    ) async {
      final Offset at = Offset(num(p, 'x'), num(p, 'y'));
      final int hold = num(p, 'ms', 60).round();
      await send(<Offset>[at, at], hold);
      return developer.ServiceExtensionResponse.result(
        jsonEncode(<String, Object>{'ok': true}),
      );
    });
    // 往当前聚焦的输入框里写字（模拟器键盘注入同样进不来）
    developer.registerExtension('ext.agent.text', (
      String _,
      Map<String, String> p,
    ) async {
      final BuildContext? ctx = FocusManager.instance.primaryFocus?.context;
      final EditableTextState? st = ctx
          ?.findAncestorStateOfType<EditableTextState>();
      final String t = p['text'] ?? '';
      st?.userUpdateTextEditingValue(
        TextEditingValue(
          text: t,
          selection: TextSelection.collapsed(offset: t.length),
        ),
        SelectionChangedCause.keyboard,
      );
      return developer.ServiceExtensionResponse.result(
        jsonEncode(<String, Object>{'ok': st != null}),
      );
    });
    developer.registerExtension('ext.agent.drag', (
      String _,
      Map<String, String> p,
    ) async {
      final Offset a = Offset(num(p, 'x'), num(p, 'y'));
      final Offset b = Offset(num(p, 'x2'), num(p, 'y2'));
      final int steps = num(p, 'steps', 12).round().clamp(2, 120);
      final int ms = num(p, 'ms', 300).round();
      await send(<Offset>[
        for (int i = 0; i <= steps; i++) Offset.lerp(a, b, i / steps)!,
      ], (ms / steps).round().clamp(1, 1000));
      return developer.ServiceExtensionResponse.result(
        jsonEncode(<String, Object>{'ok': true}),
      );
    });
  }

  /// 关闭语义树（热重载 / 测试收尾用）。
  static void disableSemantics() {
    _semanticsHandle?.dispose();
    _semanticsHandle = null;
  }

  /// 导出组件树 JSON 字符串。
  static String dumpTree({int maxDepth = 40, int maxNodes = 4000}) {
    if (!kAgentBridgeEnabled) return '{"enabled":false}';

    final List<AgentNode> nodes = <AgentNode>[];
    void walk(Element el, int depth) {
      if (depth > maxDepth || nodes.length >= maxNodes) return;
      final Widget w = el.widget;
      final RenderObject? ro = el.renderObject;
      Rect? rect;
      if (ro is RenderBox && ro.hasSize && ro.attached) {
        try {
          final Offset off = ro.localToGlobal(Offset.zero);
          rect = off & ro.size;
        } catch (_) {}
      }
      String? text;
      if (w is Text) {
        text = w.data;
      } else if (w is RichText) {
        text = w.text.toPlainText();
      }
      nodes.add(
        AgentNode(
          type: w.runtimeType.toString(),
          depth: depth,
          key: w.key?.toString(),
          text: text,
          rect: rect,
        ),
      );
      el.visitChildren((Element child) => walk(child, depth + 1));
    }

    final Element? root = WidgetsBinding.instance.rootElement;
    if (root != null) walk(root, 0);
    return _encode(nodes);
  }

  static String _encode(List<AgentNode> nodes) {
    final StringBuffer b = StringBuffer('{"enabled":true,"count":');
    b.write(nodes.length);
    b.write(',"nodes":[');
    for (int i = 0; i < nodes.length; i++) {
      if (i > 0) b.write(',');
      final AgentNode n = nodes[i];
      b.write('{"type":"${_esc(n.type)}","depth":${n.depth}');
      if (n.key != null) b.write(',"key":"${_esc(n.key!)}"');
      if (n.text != null && n.text!.isNotEmpty) {
        b.write(',"text":"${_esc(n.text!)}"');
      }
      if (n.rect != null) {
        final Rect r = n.rect!;
        b.write(
          ',"rect":{"x":${r.left.toStringAsFixed(1)},'
          '"y":${r.top.toStringAsFixed(1)},'
          '"w":${r.width.toStringAsFixed(1)},'
          '"h":${r.height.toStringAsFixed(1)}}',
        );
      }
      b.write('}');
    }
    b.write(']}');
    return b.toString();
  }

  static String _esc(Object? v) {
    return (v ?? '')
        .toString()
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
  }

  /// 把当前画面截成 PNG 并返回字节。
  ///
  /// 走 `RepaintBoundary` 路径：优先用根 `RenderRepaintBoundary`；没有则退化为
  /// `ui.Image` 直接合成（用 `SchedulerBinding` 等一帧再画）。
  static Future<Uint8List?> capture({double pixelRatio = 2.0}) async {
    if (!kAgentBridgeEnabled) return null;
    try {
      final RenderObject? ro =
          WidgetsBinding.instance.rootElement?.renderObject;
      ui.Image? img;
      if (ro is RenderRepaintBoundary && ro.hasSize) {
        img = await ro.toImage(pixelRatio: pixelRatio);
      } else {
        // 退化路径：等一帧后把 RenderView 画进 PictureRecorder
        await SchedulerBinding.instance.endOfFrame;
        final RenderView rv = WidgetsBinding.instance.renderViews.first;
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas canvas = Canvas(recorder);
        canvas.scale(pixelRatio);
        final PaintingContext ctx = PaintingContext(
          ContainerLayer(),
          Offset.zero & rv.size,
        );
        rv.paint(ctx, Offset.zero);
        final ui.Picture pic = recorder.endRecording();
        img = await pic.toImage(
          (rv.size.width * pixelRatio).round(),
          (rv.size.height * pixelRatio).round(),
        );
      }
      final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[AgentBridge] capture failed: $e');
      return null;
    }
  }

  /// 写截图到设备目录（debug 用）。
  ///
  /// Android: /sdcard/agent/。返回写入路径，失败返回 null。
  static Future<String?> screenshot({String name = 'shot'}) async {
    if (!kAgentBridgeEnabled) return null;
    try {
      final Uint8List? bytes = await capture();
      if (bytes == null) return null;
      final String? saved = await saveAgentScreenshot(bytes, name);
      if (saved == null) return null;
      final String path = saved;
      debugPrint('[AgentBridge] screenshot -> $path');
      return path;
    } catch (e) {
      debugPrint('[AgentBridge] screenshot failed: $e');
      return null;
    }
  }

  /// 把组件树 JSON 打到日志（logcat 可抓）。
  static void logTree() {
    if (!kAgentBridgeEnabled) return;
    debugPrint('[AgentBridge] tree=${dumpTree()}');
  }
}
