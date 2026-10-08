import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:system_panel/agent/llm_client.dart';
import 'package:system_panel/agent/llm_gateway.dart';

/// LlmGateway（CopyLlmGateway 的真实现）——把 t9 的 LlmClient 插进 copy.dart
/// 的最小面。全离线：http 层用假 Client，不打真网。
void main() {
  /// OpenAI 兼容端点的假实现：按 handler 回应
  LlmClient clientOf(
    Future<http.Response> Function(String body) handler, {
    Duration? delay,
  }) {
    return LlmClient(
      config: const LlmConfig(apiKey: 'sk-test'),
      httpClient: _FakeHttp(handler, delay: delay),
    );
  }

  http.Response okJson(String content) => http.Response(
        jsonEncode(<String, dynamic>{
          'choices': <dynamic>[
            <String, dynamic>{
              'message': <String, dynamic>{'role': 'assistant', 'content': content},
            },
          ],
        }),
        200,
        headers: <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
      );

  group('configured', () {
    test('没配 Key = false，complete 直接 null（零网络）', () async {
      bool called = false;
      final LlmGateway gw = LlmGateway(LlmClient(
        config: const LlmConfig(apiKey: ''),
        httpClient: _FakeHttp((String _) async {
          called = true;
          return okJson('x');
        }),
      ));
      expect(gw.configured, isFalse);
      expect(
        await gw.complete(messages: const <Map<String, dynamic>>[
          <String, dynamic>{'role': 'user', 'content': 'hi'},
        ]),
        isNull,
      );
      expect(called, isFalse); // 没发请求
    });

    test('配了 Key = true', () {
      final LlmGateway gw = LlmGateway(clientOf((String _) async => okJson('x')));
      expect(gw.configured, isTrue);
    });
  });

  group('complete', () {
    test('成功：回 LLM 原文（标签由调用方剥）', () async {
      final LlmGateway gw = LlmGateway(
        clientOf((String _) async => okJson('[smug]哼，行吧。')),
      );
      final String? out = await gw.complete(
        messages: const <Map<String, dynamic>>[
          <String, dynamic>{'role': 'system', 'content': 's'},
          <String, dynamic>{'role': 'user', 'content': 'u'},
        ],
      );
      expect(out, '[smug]哼，行吧。');
    });

    test('HTTP 500 → null（调用方走兜底）', () async {
      final LlmGateway gw = LlmGateway(
        clientOf((String _) async => http.Response('boom', 500)),
      );
      expect(
        await gw.complete(messages: const <Map<String, dynamic>>[]),
        isNull,
      );
    });

    test('空话（空白正文）→ null', () async {
      final LlmGateway gw = LlmGateway(
        clientOf((String _) async => okJson('   ')),
      );
      expect(
        await gw.complete(messages: const <Map<String, dynamic>>[]),
        isNull,
      );
    });

    test('调用方 timeout 比假端点快 → null（兜底不被吊死）', () async {
      final LlmGateway gw = LlmGateway(
        clientOf(
          (String _) async => okJson('late'),
          delay: const Duration(milliseconds: 400),
        ),
      );
      expect(
        await gw.complete(
          messages: const <Map<String, dynamic>>[],
          timeout: const Duration(milliseconds: 30),
        ),
        isNull,
      );
    });

    test('多模态消息照原样上行（image_url 不丢）', () async {
      String? sent;
      final LlmGateway gw = LlmGateway(clientOf((String body) async {
        sent = body;
        return okJson('x');
      }));
      await gw.complete(messages: const <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'content': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'text': '看这张'},
            <String, dynamic>{
              'type': 'image_url',
              'image_url': <String, String>{'url': 'data:image/png;base64,AAA'},
            },
          ],
        },
      ]);
      expect(sent, isNotNull);
      expect(sent!, contains('image_url'));
      expect(sent!, contains('data:image/png;base64,AAA'));
      expect(sent!, contains('看这张'));
    });
  });
}

/// 假 http 层：把 Request 折成 Response 交回
class _FakeHttp extends http.BaseClient {
  _FakeHttp(this.handler, {this.delay});

  final Future<http.Response> Function(String body) handler;
  final Duration? delay;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.Request r = request as http.Request;
    if (delay != null) await Future<void>.delayed(delay!);
    final http.Response resp = await handler(r.body);
    return http.StreamedResponse(
      Stream<List<int>>.value(resp.bodyBytes),
      resp.statusCode,
      headers: resp.headers,
    );
  }
}
