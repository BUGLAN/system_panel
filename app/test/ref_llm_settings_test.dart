import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/settings_store.dart';

/// LLM 设置页的采样两项：温度 / 上下文长度（流式开关 G2.3① 已删）。
///
/// 参考稿没有 LLM 设置这一块（它只有音效/秘籍/彩蛋/重置四行），所以这一组
/// 是按「补全设计稿缺失组件」新增的。新增功能最怕**能存能显但没人消费**，
/// 所以这里直接断言**请求体**里出现了对应的字段 —— 设置页改了，请求真的变。
/// 主链路 / 视觉校验也带上它们的断言在 g_llm_vision_test.dart。
void main() {
  /// 抓一次请求体
  Future<Map<String, dynamic>> capture({
    double? temperature,
    int contextLen = 0,
    double? asked,
    int? askedTokens,
  }) async {
    late Map<String, dynamic> body;
    final LlmClient client = LlmClient(
      config: LlmConfig(
        apiKey: 'k',
        baseUrl: 'https://example.test',
        model: 'm',
        temperature: temperature,
        contextLen: contextLen,
      ),
      httpClient: MockClient((http.Request r) async {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <dynamic>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': '嗯。'},
              },
            ],
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    await client.chat(
      messages: <LlmMessage>[LlmMessage.user('测试')],
      temperature: asked,
      maxTokens: askedTokens,
    );
    client.close();
    return body;
  }

  test('温度：配置给了就进请求体', () async {
    final Map<String, dynamic> b = await capture(temperature: 1.2);
    expect(b['temperature'], 1.2);
  });

  test('温度：调用点覆盖优先于设置页', () async {
    final Map<String, dynamic> b = await capture(temperature: .2, asked: .9);
    expect(b['temperature'], .9);
  });

  test('温度：都没给就不带这个字段（交端点默认）', () async {
    final Map<String, dynamic> b = await capture();
    expect(b.containsKey('temperature'), isFalse);
  });

  test('上下文长度：作为 max_tokens 的**上限**钳制调用点', () async {
    // 调用点要 8192，设置页限 2048 → 取 2048
    final Map<String, dynamic> small = await capture(
      contextLen: 2048,
      askedTokens: 8192,
    );
    expect(small['max_tokens'], 2048);
    // 调用点要 512，设置页限 8192 → 仍取 512（上限不顶掉小预算）
    final Map<String, dynamic> kept = await capture(
      contextLen: 8192,
      askedTokens: 512,
    );
    expect(kept['max_tokens'], 512);
  });

  test('上下文长度 0 = 不钳制，原样用调用点', () async {
    final Map<String, dynamic> b = await capture(askedTokens: 4096);
    expect(b['max_tokens'], 4096);
  });

  test('请求体永不带 stream（G2.3①：客户端整包解析，SSE 必挂）', () async {
    expect((await capture()).containsKey('stream'), isFalse);
    expect(
      (await capture(temperature: 1.2, contextLen: 2048)).containsKey('stream'),
      isFalse,
    );
  });

  test('设置页的两个字段走 AgentSettings 往返不丢', () {
    // 这是「保存配置」那一颗键真正做的事：toJson → fromJson
    const AgentSettings s = AgentSettings(temperature: .35, contextLen: 8192);
    final AgentSettings back = AgentSettings.fromJson(
      jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      fallback: const AgentSettings(),
    );
    expect(back.temperature, .35);
    expect(back.contextLen, 8192);
  });

  test('老存档缺这两个 key：落回默认，不清档', () {
    final AgentSettings back = AgentSettings.fromJson(<String, dynamic>{
      'baseUrl': 'https://old.test',
      'apiKey': 'old',
    }, fallback: const AgentSettings());
    expect(back.baseUrl, 'https://old.test');
    expect(back.temperature, AgentSettings.kDefaultTemperature);
    expect(back.contextLen, AgentSettings.kDefaultContextLen);
  });
}
