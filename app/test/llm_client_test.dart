import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/llm_telemetry.dart';

/// LlmClient 单测（docs/18 §2.4 / §3.1-T4）。
/// 全部走 MockClient，不打真网。
///
/// 实测事实（ENV.md round 15）：`deepseek-v4.1flash` 在端点 400，
/// 实际可用 `deepseek-flash` / `deepseek-v4-pro` —— 客户端做别名归一化。
void main() {
  http.Response okBody(String content) => http.Response(
    jsonEncode(<String, dynamic>{
      'choices': <dynamic>[
        <String, dynamic>{
          'message': <String, dynamic>{'content': content},
        },
      ],
    }),
    200,
    // ⚠️ 必须带 content-type：http 1.6.0 只在 `application/json` 时默认 UTF-8，
    //    否则回落 latin1 —— 中文正文会在**构造**这一侧就抛
    //    「Contains invalid characters」（真端点也是这个头，见 2026-10-12 实测）。
    headers: <String, String>{'content-type': 'application/json'},
  );

  /// 推理模型「思考把预算吃光」的应答：HTTP 200、正文空、finish_reason=length。
  /// 真机实测（2026-10-12）：同一端点 6 次里 2 次长这样，正文空 → 她静默退回模板。
  http.Response starvedBody({int reasoning = 512}) => http.Response(
    jsonEncode(<String, dynamic>{
      'choices': <dynamic>[
        <String, dynamic>{
          'finish_reason': 'length',
          'message': <String, dynamic>{
            'content': '',
            'reasoning_content': '想…',
          },
        },
      ],
      'usage': <String, dynamic>{
        'completion_tokens': reasoning,
        'completion_tokens_details': <String, dynamic>{
          'reasoning_tokens': reasoning,
        },
      },
    }),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );

  group('思考吃光预算 → 抬预算重来（不以失败论，也不静默退回模板）', () {
    test('首发出空正文 → 抬 max_tokens 重来一次，第二次拿到正文', () async {
      final List<int> budgets = <int>[];
      int calls = 0;
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: MockClient((http.Request r) async {
          calls++;
          budgets.add(
            (jsonDecode(r.body) as Map<String, dynamic>)['max_tokens'] as int,
          );
          return calls == 1 ? starvedBody() : okBody('[smug]哼。');
        }),
      );
      final LlmReply r = await client.chat(
        messages: <LlmMessage>[LlmMessage.user('hi')],
        maxTokens: 512,
      );
      expect(calls, 2, reason: '应当重来一次');
      expect(budgets, <int>[512, 1536], reason: '第二次预算要抬上去（×3）');
      expect(r.text, '[smug]哼。');
      expect(r.starvedByThinking, isFalse);
    });

    test('正常回复不触发重来（只发一次）', () async {
      int calls = 0;
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: MockClient((http.Request r) async {
          calls++;
          return okBody('正常一句');
        }),
      );
      await client.chat(
        messages: <LlmMessage>[LlmMessage.user('hi')],
        maxTokens: 512,
      );
      expect(calls, 1);
    });

    test('两次都被吃光 → 不无限重试，返回空正文交给上层兜底', () async {
      int calls = 0;
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: MockClient((http.Request r) async {
          calls++;
          return starvedBody();
        }),
      );
      final LlmReply r = await client.chat(
        messages: <LlmMessage>[LlmMessage.user('hi')],
        maxTokens: 512,
      );
      expect(calls, 2, reason: '只抬一次，不无限重试');
      expect(r.ok, isTrue, reason: 'HTTP 200 不是失败');
      expect(r.text, isEmpty);
      expect(r.starvedByThinking, isTrue);
    });

    test('预算已封顶（4096）时不再白跑第二趟', () async {
      int calls = 0;
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: MockClient((http.Request r) async {
          calls++;
          return starvedBody(reasoning: 4096);
        }),
      );
      await client.chat(
        messages: <LlmMessage>[LlmMessage.user('hi')],
        maxTokens: kMaxEscalatedTokens,
      );
      expect(calls, 1);
    });
  });

  group('LlmConfig · 模型名别名归一化', () {
    test('deepseek-v4.1flash → deepseek-flash（端点没有 v4.1flash）', () {
      const LlmConfig c = LlmConfig(model: 'deepseek-v4.1flash');
      expect(c.normalizedModel, 'deepseek-flash');
      expect(c.modelWasNormalized, isTrue);
    });

    test('大小写与变体同样归一', () {
      expect(
        const LlmConfig(model: 'V4.1FLASH').normalizedModel,
        'deepseek-flash',
      );
      expect(
        const LlmConfig(model: 'deepseek-v4.1-flash').normalizedModel,
        'deepseek-flash',
      );
      expect(
        const LlmConfig(model: 'v4.1flash').normalizedModel,
        'deepseek-flash',
      );
    });

    test('端点实际存在的模型名原样透传', () {
      expect(
        const LlmConfig(model: 'deepseek-v4-pro').normalizedModel,
        'deepseek-v4-pro',
      );
      expect(
        const LlmConfig(model: 'deepseek-v4-pro').modelWasNormalized,
        isFalse,
      );
      expect(
        const LlmConfig(model: 'gpt-4o-mini').normalizedModel,
        'gpt-4o-mini',
      );
    });

    test('默认值：官方 base + 宿主钦定的默认模型名', () {
      const LlmConfig c = LlmConfig();
      expect(c.baseUrl, 'https://api.deepseek.com');
      expect(c.model, 'deepseek-v4.1flash');
    });

    test('按调用覆盖思考档位：覆盖 > 配置（台词关思考，拆解留思考）', () async {
      final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
      LlmClient withConfig(String? effort) => LlmClient(
        config: LlmConfig(apiKey: 'k', reasoningEffort: effort ?? ''),
        httpClient: MockClient((http.Request r) async {
          sent.add(jsonDecode(r.body) as Map<String, dynamic>);
          return okBody('ok');
        }),
      );

      // ① 配置 low + 调用点传 none → 以调用点为准（台词链路就是这么走的）
      await withConfig('low').chat(
        messages: <LlmMessage>[LlmMessage.user('hi')],
        maxTokens: 1024,
        reasoningEffort: 'none',
      );
      expect(sent.last['reasoning_effort'], 'none');
      expect(sent.last['max_tokens'], 1024);

      // ② 不传覆盖 → 用配置（拆解 / 工具循环走这条）
      await withConfig('low')
          .chat(messages: <LlmMessage>[LlmMessage.user('hi')], maxTokens: 2048);
      expect(sent.last['reasoning_effort'], 'low');

      // ③ 配置为空 + 不传覆盖 → 整个字段不发（端点自己决定）
      await withConfig(null)
          .chat(messages: <LlmMessage>[LlmMessage.user('hi')]);
      expect(sent.last.containsKey('reasoning_effort'), isFalse);

      // ④ 配置为空但调用点指定 → 照样发得出去
      await withConfig(null).chat(
        messages: <LlmMessage>[LlmMessage.user('hi')],
        reasoningEffort: 'none',
      );
      expect(sent.last['reasoning_effort'], 'none');
    });

    test('端点拼接：base / 尾斜杠 / v1 / 写全 三种填法', () {
      expect(
        const LlmConfig(baseUrl: 'https://api.deepseek.com').endpoint,
        'https://api.deepseek.com/chat/completions',
      );
      expect(
        const LlmConfig(baseUrl: 'https://api.deepseek.com/').endpoint,
        'https://api.deepseek.com/chat/completions',
      );
      expect(
        const LlmConfig(baseUrl: 'https://x.example/v1/').endpoint,
        'https://x.example/v1/chat/completions',
      );
      expect(
        const LlmConfig(baseUrl: 'https://x.example/v1/chat/completions')
            .endpoint,
        'https://x.example/v1/chat/completions',
      );
      expect(
        const LlmConfig(baseUrl: '').endpoint,
        'https://api.deepseek.com/chat/completions',
      );
    });
  });

  group('LlmClient · 请求与应答', () {
    test('无 Key 直接按 noKey 兜底，一个请求都不发', () async {
      int calls = 0;
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: ''),
        httpClient: MockClient((http.Request r) async {
          calls++;
          return okBody('x');
        }),
      );
      final LlmReply r = await client.chat(
        messages: <LlmMessage>[LlmMessage.user('hi')],
      );
      expect(r.ok, isFalse);
      expect(r.failure, LlmFailure.noKey);
      expect(calls, 0);
    });

    test('请求体：归一化模型名 + Bearer 头 + 端点正确', () async {
      Uri? url;
      Map<String, String>? headers;
      Map<String, dynamic>? body;
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'sk-test', model: 'deepseek-v4.1flash'),
        httpClient: MockClient((http.Request r) async {
          url = r.url;
          headers = r.headers;
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return okBody('pong');
        }),
      );
      final LlmReply r = await client.chat(
        messages: <LlmMessage>[LlmMessage.system('sys'), LlmMessage.user('u')],
      );
      expect(r.ok, isTrue);
      expect(r.text, 'pong');
      expect(r.model, 'deepseek-flash'); // 归一化后的名字回填
      expect(url.toString(), 'https://api.deepseek.com/chat/completions');
      expect(headers!['Authorization'], 'Bearer sk-test');
      expect(body!['model'], 'deepseek-flash');
      expect((body!['messages'] as List<dynamic>).length, 2);
    });

    test('多模态消息：图片变 image_url parts（data URL 直通）', () async {
      Map<String, dynamic>? body;
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: MockClient((http.Request r) async {
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return okBody('seen');
        }),
      );
      final LlmReply r = await client.chat(
        messages: <LlmMessage>[
          LlmMessage.user(
            '看这张',
            images: <String>['data:image/jpeg;base64,QUJD'],
          ),
        ],
      );
      expect(r.ok, isTrue);
      final List<dynamic> parts =
          ((body!['messages'] as List<dynamic>).first
                  as Map<String, dynamic>)['content']
              as List<dynamic>;
      expect(parts[0]['type'], 'text');
      expect(parts[0]['text'], '看这张');
      expect(parts[1]['type'], 'image_url');
      expect(parts[1]['image_url']['url'], 'data:image/jpeg;base64,QUJD');
    });

    test(
      'function calling：tools 发出 + tool_calls 解析（arguments 字符串→Map）',
      () async {
        Map<String, dynamic>? body;
        final LlmClient client = LlmClient(
          config: const LlmConfig(apiKey: 'sk-test'),
          httpClient: MockClient((http.Request r) async {
            body = jsonDecode(r.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'choices': <dynamic>[
                  <String, dynamic>{
                    'message': <String, dynamic>{
                      'content': '',
                      'tool_calls': <dynamic>[
                        <String, dynamic>{
                          'id': 'call_1',
                          'type': 'function',
                          'function': <String, dynamic>{
                            'name': 'get_status',
                            'arguments': '{"want":"lv"}',
                          },
                        },
                      ],
                    },
                  },
                ],
              }),
              200,
            );
          }),
        );
        final LlmReply r = await client.chat(
          messages: <LlmMessage>[LlmMessage.user('查状态')],
          tools: <LlmTool>[
            LlmTool(
              name: 'get_status',
              description: '查 LV/金币/连击',
              parameters: <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{},
              },
            ),
          ],
        );
        expect(r.ok, isTrue);
        final List<dynamic> tools = body!['tools'] as List<dynamic>;
        expect((tools.first as Map<String, dynamic>)['type'], 'function');
        expect(
          ((tools.first as Map<String, dynamic>)['function']
              as Map<String, dynamic>)['name'],
          'get_status',
        );
        expect(r.toolCalls.single.id, 'call_1');
        expect(r.toolCalls.single.name, 'get_status');
        expect(r.toolCalls.single.arguments, <String, dynamic>{'want': 'lv'});
      },
    );

    test('arguments 坏 JSON → 空参数兜底，不炸', () async {
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: MockClient(
          (http.Request r) async => http.Response(
            jsonEncode(<String, dynamic>{
              'choices': <dynamic>[
                <String, dynamic>{
                  'message': <String, dynamic>{
                    'content': '',
                    'tool_calls': <dynamic>[
                      <String, dynamic>{
                        'id': 'c',
                        'function': <String, dynamic>{
                          'name': 'x',
                          'arguments': '{broken',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          ),
        ),
      );
      final LlmReply r = await client.chat(
        messages: <LlmMessage>[LlmMessage.user('u')],
      );
      expect(r.ok, isTrue);
      expect(r.toolCalls.single.arguments, isEmpty);
    });

    test('传输层失败重试 1 次后成功', () async {
      int calls = 0;
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: MockClient((http.Request r) async {
          calls++;
          if (calls == 1) throw http.ClientException('boom');
          return okBody('ok');
        }),
      );
      final LlmReply r = await client.chat(
        messages: <LlmMessage>[LlmMessage.user('hi')],
      );
      expect(r.ok, isTrue);
      expect(calls, 2);
    });

    test('超时重试 1 次仍超时 → timeout 兜底（不抛异常）', () async {
      int calls = 0;
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((http.Request r) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 90));
          return okBody('late');
        }),
      );
      final LlmReply r = await client.chat(
        messages: <LlmMessage>[LlmMessage.user('hi')],
      );
      expect(r.ok, isFalse);
      expect(r.failure, LlmFailure.timeout);
      expect(calls, 2);
      expect(r.detail, contains('已重试 1 次'));
    });

    test('HTTP 401 不重试（重试也不会好），按 httpError 兜底', () async {
      int calls = 0;
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'bad'),
        httpClient: MockClient((http.Request r) async {
          calls++;
          return http.Response('{"error":"auth"}', 401);
        }),
      );
      final LlmReply r = await client.chat(
        messages: <LlmMessage>[LlmMessage.user('hi')],
      );
      expect(r.ok, isFalse);
      expect(r.failure, LlmFailure.httpError);
      expect(calls, 1);
      expect(r.detail, contains('HTTP 401'));
    });

    group('200 但结构坏 → badResponse（逐样兜底）', () {
      Future<LlmFailure> kindOf(String body) async {
        final LlmClient client = LlmClient(
          config: const LlmConfig(apiKey: 'k'),
          httpClient: MockClient(
            (http.Request r) async => http.Response(body, 200),
          ),
        );
        final LlmReply r = await client.chat(
          messages: <LlmMessage>[LlmMessage.user('hi')],
        );
        return r.failure!;
      }

      test(
        '纯文本',
        () async => expect(await kindOf('not json'), LlmFailure.badResponse),
      );
      test(
        'JSON 数组',
        () async => expect(await kindOf('[1,2]'), LlmFailure.badResponse),
      );
      test(
        '缺 choices',
        () async => expect(await kindOf('{}'), LlmFailure.badResponse),
      );
      test(
        'choices 空',
        () async =>
            expect(await kindOf('{"choices":[]}'), LlmFailure.badResponse),
      );
      test(
        '缺 message',
        () async => expect(
          await kindOf('{"choices":[{"x":1}]}'),
          LlmFailure.badResponse,
        ),
      );
    });

    test('ping() 发**真实形状**探测请求（docs/22 R1：不再是 maxTokens 8 的假绿灯）', () async {
      Map<String, dynamic>? body;
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: MockClient((http.Request r) async {
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return okBody('pong');
        }),
      );
      final LlmReply r = await client.ping();
      expect(r.ok, isTrue);
      // 一句系统提示 + 一句用户话（旧版只有 user('ping') 且 max_tokens=8）
      expect((body!['messages'] as List<dynamic>).length, 2);
      expect(body!['max_tokens'], 512);
      expect(body!['reasoning_effort'], LlmConfig.kDefaultReasoningEffort);
    });

    test('reasoning_effort：默认 low 透传；可调 max；空串 = 不带该参数', () async {
      Future<Map<String, dynamic>> bodyOf(LlmConfig cfg) async {
        Map<String, dynamic>? body;
        final LlmClient c = LlmClient(
          config: cfg,
          httpClient: MockClient((http.Request r) async {
            body = jsonDecode(r.body) as Map<String, dynamic>;
            return okBody('x');
          }),
        );
        await c.chat(messages: <LlmMessage>[LlmMessage.user('hi')]);
        return body!;
      }

      expect(
        (await bodyOf(const LlmConfig(apiKey: 'k')))['reasoning_effort'],
        'low',
      );
      expect(
        (await bodyOf(
          const LlmConfig(apiKey: 'k', reasoningEffort: 'max'),
        ))['reasoning_effort'],
        'max',
      );
      expect(
        (await bodyOf(const LlmConfig(apiKey: 'k', reasoningEffort: '')))
            .containsKey('reasoning_effort'),
        isFalse,
      );
    });

    test('遥测（docs/22 §2.0）：每次应答计数 + 失败留类别与 detail', () async {
      LlmTelemetry.reset();
      // ① 成功
      final LlmClient ok = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: MockClient((http.Request r) async => okBody('hi')),
      );
      await ok.chat(messages: <LlmMessage>[LlmMessage.user('x')]);
      expect(LlmTelemetry.calls, 1);
      expect(LlmTelemetry.ok, 1);
      expect(LlmTelemetry.failures, 0);
      // ② HTTP 500：类别 + detail 都要留住
      final LlmClient bad = LlmClient(
        config: const LlmConfig(apiKey: 'k'),
        httpClient: MockClient(
          (http.Request r) async => http.Response('{"error":"boom"}', 500),
        ),
      );
      final LlmReply r = await bad.chat(
        messages: <LlmMessage>[LlmMessage.user('x')],
      );
      expect(r.failure, LlmFailure.httpError);
      expect(LlmTelemetry.calls, 2);
      expect(LlmTelemetry.failures, 1);
      expect(LlmTelemetry.byKind[LlmFailure.httpError], 1);
      expect(LlmTelemetry.lastDetail, contains('500'));
      expect(LlmTelemetry.lastDetail, contains('boom'));
      // ③ 无 Key 短路也算一次失败（最容易被漏记的一类「她哑了」）
      final LlmClient none = LlmClient(
        config: const LlmConfig(),
        httpClient: MockClient((http.Request r) async => okBody('x')),
      );
      await none.chat(messages: <LlmMessage>[LlmMessage.user('x')]);
      expect(LlmTelemetry.byKind[LlmFailure.noKey], 1);
      expect(LlmTelemetry.calls, 3);
      LlmTelemetry.reset();
      expect(LlmTelemetry.calls, 0);
      expect(LlmTelemetry.lastDetail, isNull);
    });

    test('严格模式不重试（开发期一次就报真因，验收 F-5）；release 语义重试 1 次', () async {
      Future<int> attemptsOf(bool strict) async {
        int n = 0;
        final LlmClient c = LlmClient(
          config: LlmConfig(apiKey: 'k', strict: strict),
          httpClient: MockClient((http.Request r) async {
            n++;
            throw http.ClientException('boom');
          }),
        );
        final LlmReply r = await c.chat(
          messages: <LlmMessage>[LlmMessage.user('x')],
        );
        expect(r.failure, LlmFailure.network);
        return n;
      }

      expect(await attemptsOf(true), 1, reason: '严格模式：一次就报，不重试');
      expect(await attemptsOf(false), 2, reason: 'release：传输层失败重试 1 次');
    });

    test('LlmReply.hasText：HTTP 200 但正文为空不算「拿到话」（验收 F-2）', () {
      expect(const LlmReply.success(text: '嗯。').hasText, isTrue);
      expect(const LlmReply.success(text: '   ').hasText, isFalse);
      expect(const LlmReply.success(text: '').hasText, isFalse);
      expect(
        const LlmReply.failure(LlmFailure.noKey, '未配置 API Key').hasText,
        isFalse,
      );
    });
  });
}
