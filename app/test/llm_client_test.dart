import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:system_panel/agent/llm_client.dart';

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
  );

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
      final LlmReply r = await client.chat(messages: <LlmMessage>[
        LlmMessage.user('hi'),
      ]);
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
      final LlmReply r = await client.chat(messages: <LlmMessage>[
        LlmMessage.system('sys'),
        LlmMessage.user('u'),
      ]);
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
      final LlmReply r = await client.chat(messages: <LlmMessage>[
        LlmMessage.user('看这张', images: <String>['data:image/jpeg;base64,QUJD']),
      ]);
      expect(r.ok, isTrue);
      final List<dynamic> parts =
          ((body!['messages'] as List<dynamic>).first
              as Map<String, dynamic>)['content'] as List<dynamic>;
      expect(parts[0]['type'], 'text');
      expect(parts[0]['text'], '看这张');
      expect(parts[1]['type'], 'image_url');
      expect(parts[1]['image_url']['url'], 'data:image/jpeg;base64,QUJD');
    });

    test('function calling：tools 发出 + tool_calls 解析（arguments 字符串→Map）', () async {
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
    });

    test('arguments 坏 JSON → 空参数兜底，不炸', () async {
      final LlmClient client = LlmClient(
        config: const LlmConfig(apiKey: 'sk-test'),
        httpClient: MockClient((http.Request r) async => http.Response(
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
        )),
      );
      final LlmReply r = await client.chat(messages: <LlmMessage>[
        LlmMessage.user('u'),
      ]);
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
      final LlmReply r = await client.chat(messages: <LlmMessage>[
        LlmMessage.user('hi'),
      ]);
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
      final LlmReply r = await client.chat(messages: <LlmMessage>[
        LlmMessage.user('hi'),
      ]);
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
      final LlmReply r = await client.chat(messages: <LlmMessage>[
        LlmMessage.user('hi'),
      ]);
      expect(r.ok, isFalse);
      expect(r.failure, LlmFailure.httpError);
      expect(calls, 1);
      expect(r.detail, contains('HTTP 401'));
    });

    group('200 但结构坏 → badResponse（逐样兜底）', () {
      Future<LlmFailure> kindOf(String body) async {
        final LlmClient client = LlmClient(
          config: const LlmConfig(apiKey: 'k'),
          httpClient: MockClient((http.Request r) async => http.Response(body, 200)),
        );
        final LlmReply r = await client.chat(messages: <LlmMessage>[
          LlmMessage.user('hi'),
        ]);
        return r.failure!;
      }

      test('纯文本', () async => expect(await kindOf('not json'), LlmFailure.badResponse));
      test('JSON 数组', () async => expect(await kindOf('[1,2]'), LlmFailure.badResponse));
      test('缺 choices', () async => expect(await kindOf('{}'), LlmFailure.badResponse));
      test('choices 空', () async => expect(await kindOf('{"choices":[]}'), LlmFailure.badResponse));
      test('缺 message', () async => expect(await kindOf('{"choices":[{"x":1}]}'), LlmFailure.badResponse));
    });

    test('ping() 发最小探测请求', () async {
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
      expect((body!['messages'] as List<dynamic>).length, 1);
      expect(body!['max_tokens'], 8);
    });
  });
}
