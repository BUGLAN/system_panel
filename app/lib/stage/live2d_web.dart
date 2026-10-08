import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

/// ═══════════════════════════════════════════════════════════
///  她本人（`#stage`）—— 路线 ②：用原型自己的播放器
///
///  为什么不是原生插件：见 `app/STAGE-OPTIONS.md`。一句话 —— 原型的播放器认识的
///  是**原始 prefab 数据**，用它的渲染结果与原型的**保证一致**；换第三方插件既要
///  写转换器、又要赌渲染。实测也证明：`flutter_live2d` 能加载、渲染循环在跑，
///  就是不上屏（换标准模型 Hiyori 也一样），而同一份数据在模拟器浏览器里正常。
///
///  ## 为什么要起一个本机 HTTP 服务
///  播放器是用 `fetch` 读清单和资源的，`file://` 会被 CORS 拦掉（原型
///  `README-source.md` 里也写了「必须通过 http 服务器打开」）。所以这里在
///  `127.0.0.1` 上起一个只服务 APK 内资产的迷你服务，WebView 去 `http://` 拿。
///
///  路由（刻意让清单的**相对路径**能对上）：
///    `/`               → `assets/stage/stage.html`
///    `/stage.js`       → `assets/stage/stage.js`
///    `/vendor/<f>`     → `assets/live2d/vendor/<f>`
///    `/model/<f>`      → `assets/live2d/sakiko_orig/models/<f>`  ← 清单在这里
///    `/model/assets/<f>` → `assets/live2d/sakiko_orig/assets/<f>` ← 清单里写的相对路径
/// ═══════════════════════════════════════════════════════════
class StageServer {
  HttpServer? _server;

  int get port => _server?.port ?? 0;

  Future<int> start() async {
    if (_server != null) return port;
    final HttpServer s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen(_handle, onError: (Object _) {});
    return s.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static const Map<String, String> _mime = <String, String>{
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.png': 'image/png',
    '.moc3': 'application/octet-stream',
    '.gz': 'application/octet-stream',
    '.glsl': 'text/plain; charset=utf-8',
  };

  Future<void> _handle(HttpRequest req) async {
    final String path = Uri.decodeComponent(req.uri.path);
    final String? key = _assetKeyFor(path);
    final HttpResponse res = req.response;
    debugPrint('[stage-web] ${req.method} $path → ${key ?? "404"}');
    try {
      if (key == null) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final ByteData data = await rootBundle.load(key);
      // ⚠️ 扩展名要按**资产 key** 取，不能按 URL 路径取 —— URL `/` 根本没有扩展名，
      //    那样会回落到 `application/octet-stream`，WebView 就不会把首页当网页渲染
      //    （症状：服务端只收到 `GET /`，之后既不请求 stage.js 也不请求 vendor，
      //      `Stage` 自然一直是 undefined）。
      final String ext = key.contains('.')
          ? key.substring(key.lastIndexOf('.'))
          : '';
      res.headers.contentType = ContentType.parse(
        _mime[ext] ?? 'application/octet-stream',
      );
      res.headers.set('Cache-Control', 'no-store');
      res.add(data.buffer.asUint8List());
      await res.close();
    } on Object {
      res.statusCode = HttpStatus.notFound;
      await res.close();
    }
  }

  /// 把 URL 路径映射到 APK 里的资产 key
  static String? _assetKeyFor(String path) {
    if (path == '/' || path == '/index.html') return 'assets/stage/stage.html';
    if (path == '/stage.js') return 'assets/stage/stage.js';
    if (path.startsWith('/vendor/')) {
      return 'assets/live2d/vendor/${path.substring('/vendor/'.length)}';
    }
    if (path.startsWith('/model/assets/')) {
      return 'assets/live2d/sakiko_orig/assets/'
          '${path.substring('/model/assets/'.length)}';
    }
    // ⚠️ 清单里写的是相对路径 `assets/xxx`，而播放器是**相对页面根**去解析的
    //    （不是相对清单所在目录），所以实际请求会打到 `/assets/xxx`。
    //    这条兜住它 —— 否则症状是一串 404，然后 `error` 事件报 HTTP 404。
    if (path.startsWith('/assets/')) {
      return 'assets/live2d/sakiko_orig/assets/'
          '${path.substring('/assets/'.length)}';
    }
    if (path.startsWith('/model/')) {
      return 'assets/live2d/sakiko_orig/models/'
          '${path.substring('/model/'.length)}';
    }
    return null;
  }
}

/// WebView 里的舞台。对外只暴露"相机"和事件回调。
class Live2DWeb extends StatefulWidget {
  const Live2DWeb({
    super.key,
    this.visible = true,
    this.scale = 1,
    this.offset = Offset.zero,
    this.onReady,
    this.onFailed,
    this.onProgress,
  });

  final bool visible;

  /// 相机（原型 `_camMul` 的缩放 + 平移；这里落到 CSS 变换上）
  final double scale;
  final Offset offset;

  final VoidCallback? onReady;
  final ValueChanged<String>? onFailed;

  /// 0~1
  final ValueChanged<double>? onProgress;

  /// 清单名（服务端 `/model/` 下的文件）
  static const String manifest = 'adv_live2d_sakiko_010_casual_spring_01.json';

  @override
  State<Live2DWeb> createState() => Live2DWebState();
}

class Live2DWebState extends State<Live2DWeb> {
  final StageServer _server = StageServer();
  WebViewController? _web;
  bool _ready = false;
  bool _failed = false;
  String _lastLog = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final int port = await _server.start();
      final Uri url = Uri.parse(
        'http://127.0.0.1:$port/?src=model/${Live2DWeb.manifest}',
      );
      final WebViewController c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..addJavaScriptChannel(
          'StageBridge',
          onMessageReceived: (JavaScriptMessage m) => _onJs(m.message),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onWebResourceError: (WebResourceError e) {
              debugPrint('[stage-web] 资源错误 ${e.errorCode} ${e.description}');
            },
          ),
        )
        ..loadRequest(url);
      if (!mounted) return;
      setState(() => _web = c);
      // 给播放器一点时间把清单和资源拉完；期间主动问一次自检
      Future<void>.delayed(const Duration(seconds: 12), _probe);
    } on Object catch (e) {
      debugPrint('[stage-web] 起服务失败：$e');
      _fail('$e');
    }
  }

  void _onJs(String raw) {
    try {
      final Map<String, dynamic> m = jsonDecode(raw) as Map<String, dynamic>;
      switch (m['t']) {
        case 'ready':
          if (!mounted) return;
          setState(() => _ready = true);
          widget.onReady?.call();
        case 'progress':
          final double total = (m['total'] as num?)?.toDouble() ?? 0;
          final double loaded = (m['loaded'] as num?)?.toDouble() ?? 0;
          if (total > 0) widget.onProgress?.call((loaded / total).clamp(0, 1));
        case 'error':
          _fail('${m['message']}');
        case 'jserror':
          // WebView 里的 JS 异常只在这里能看到
          _fail('JS：${m['message']}');
      }
    } on Object catch (e) {
      debugPrint('[stage-web] 通道消息解析失败：$e ($raw)');
    }
  }

  Future<void> _probe() async {
    final WebViewController? c = _web;
    if (c == null || _ready || _failed) return;
    final Object r = await c.runJavaScriptReturningResult('Stage.probe()');
    final String s = r.toString().replaceAll(RegExp(r'^"|"$'), '');
    debugPrint('[stage-web] probe → $s');
    _lastLog = s;
    if (s.contains('"ready":true')) {
      if (mounted) setState(() => _ready = true);
      widget.onReady?.call();
    }
  }

  void _fail(String why) {
    if (_failed) return;
    debugPrint('[stage-web] 失败：$why');
    if (mounted) setState(() => _failed = true);
    widget.onFailed?.call(why);
  }

  @override
  void didUpdateWidget(covariant Live2DWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scale != widget.scale || oldWidget.offset != widget.offset) {
      final WebViewController? c = _web;
      if (c != null && _ready) {
        unawaited(
          c.runJavaScript(
            'Stage.cam(${widget.scale}, ${widget.offset.dx}, ${widget.offset.dy})',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(_server.stop());
    super.dispose();
  }

  /// 自检信息（调试用；给页面上的小字或日志）
  String get debugInfo => _lastLog;

  @override
  Widget build(BuildContext context) {
    final WebViewController? c = _web;
    if (!widget.visible || c == null) return const SizedBox.shrink();
    return Positioned.fill(
      // 平台视图会吃掉触摸，交给上面那层 Flutter UI
      child: IgnorePointer(child: WebViewWidget(controller: c)),
    );
  }
}
