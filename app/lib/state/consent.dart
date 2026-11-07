import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ═══════════════════════════════════════════════════════════
///  隐私同意（G2.1）
///
///  为什么要有它：目标原文、访谈答案、聊天内容、证据照片都会发给第三方
///  AI 服务（拆解 / 对话 / 校验），App 却没有任何告知与同意。这里只管
///  「宿主同意过哪一版协议、什么时候同意的」，LLM 闸门与首启同意页都读它。
///
///  三条约定：
///   1. **独立 key**（不进主存档）：同意是对 App 的，不是对某一份存档的——
///      「重置存档」不该顺手把同意也清掉，否则重置一次就要再签一次；
///   2. 存的是**协议版本号**：协议正文一改就把 [kPolicyVersion] 加一，
///      旧版本的同意不再算数，下次唤醒先出同意页要求重签；
///   3. **读失败一律按未同意**（隐私上宁可多问一次，也不能默认放行）。
/// ═══════════════════════════════════════════════════════════

/// 当前协议版本（《用户协议》《隐私政策》共用一个号）。
///
/// ⚠️ 改了 `assets/legal/` 下任何一篇的实质内容，就把它加一。
const int kPolicyVersion = 1;

/// 一条同意记录：同意的是哪一版、什么时候点的。
@immutable
class ConsentRecord {
  const ConsentRecord({required this.version, required this.at});

  /// 同意时的协议版本
  final int version;

  /// 同意时间（本机时间）
  final DateTime at;

  /// 是否覆盖当前版本。只认**相等**：宿主同意的是那一版正文，
  /// 降级安装到旧版本时也要重新看一眼旧正文（不拿新版的同意顶旧版）。
  bool coversVersion(int current) => version == current;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'v': version,
    'at': at.toIso8601String(),
  };

  /// 解析存档里的那一条；形状不对返回 null（= 当作没同意过）
  static ConsentRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? v = json['v'];
    final Object? at = json['at'];
    if (v is! int || at is! String) return null;
    final DateTime? t = DateTime.tryParse(at);
    if (t == null) return null;
    return ConsentRecord(version: v, at: t);
  }
}

/// 同意状态的读写（参照 [SaveFile]：可注入 prefs 便于测试）。
class ConsentStore {
  ConsentStore({
    SharedPreferencesAsync? prefs,
    this.policyVersion = kPolicyVersion,
  }) : _injected = prefs;

  /// 独立 key，带结构版本号（换存储形状时改 `v1`，与协议版本号无关）
  static const String key = 'opus-v2/consent/v1';

  /// 当前要求的协议版本（测试可注入，模拟「协议更新」）
  final int policyVersion;

  final SharedPreferencesAsync? _injected;
  SharedPreferencesAsync? _prefs;

  SharedPreferencesAsync _p() =>
      _prefs ??= _injected ?? SharedPreferencesAsync();

  /// 读出同意记录；没有 / 读坏 / 存储抛异常 → null
  Future<ConsentRecord?> load() async {
    try {
      final String? raw = await _p().getString(key);
      if (raw == null || raw.isEmpty) return null;
      return ConsentRecord.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('[consent] 读取失败，按未同意处理：$e');
      return null;
    }
  }

  /// 当前版本是否已同意（读失败 = 否）
  Future<bool> isAccepted() async =>
      (await load())?.coversVersion(policyVersion) ?? false;

  /// 记下「同意了当前版本」。返回是否真的落盘——
  /// 落盘失败时调用方仍可放行**这一次**会话（宿主当场点了同意），
  /// 只是下次启动会再问一遍。
  Future<bool> accept({DateTime? at}) async {
    final ConsentRecord r = ConsentRecord(
      version: policyVersion,
      at: at ?? DateTime.now(),
    );
    try {
      await _p().setString(key, jsonEncode(r.toJson()));
      return true;
    } catch (e) {
      debugPrint('[consent] ⚠️ 同意记录写入失败：$e');
      return false;
    }
  }

  /// 撤回同意：删记录（之后 [isAccepted] 为 false）
  Future<void> revoke() async {
    try {
      await _p().remove(key);
    } catch (e) {
      debugPrint('[consent] ⚠️ 撤回时删除记录失败：$e');
    }
  }
}
