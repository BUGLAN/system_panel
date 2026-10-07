import 'package:flutter/material.dart';

/// 已锁定的主题色（见 AGENTS.md / .stitch/DESIGN.md，勿改）
abstract final class Hud {
  /// 深蓝虚空
  static const Color voidBg = Color(0xFF0A0E1A);

  /// 电光青（主强调）
  static const Color cyan = Color(0xFF38E1FF);

  /// 次级文字
  static const Color dim = Color(0xFF9AA3B2);
}

void main() => runApp(const SystemPanelApp());

class SystemPanelApp extends StatelessWidget {
  const SystemPanelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '宿主 SYSTEM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Hud.voidBg,
      ),
      home: const EnvCheckPage(),
    );
  }
}

/// 环境自检页：验证字体三件套是否装进包里（真机/模拟器上肉眼可查）。
class EnvCheckPage extends StatelessWidget {
  const EnvCheckPage({super.key});

  /// 三套字体的正文样式（可变字重字体用 fontVariations 取粗体）
  static const TextStyle titleStyle = TextStyle(
    fontFamily: 'NotoSansSC',
    fontSize: 18,
    color: Hud.dim,
    fontVariations: <FontVariation>[FontVariation('wght', 500)],
  );

  static const TextStyle rajdhaniStyle = TextStyle(
    fontFamily: 'Rajdhani',
    fontWeight: FontWeight.w700,
    fontSize: 40,
    height: 1.1,
    color: Hud.cyan,
  );

  static const TextStyle notoStyle = TextStyle(
    fontFamily: 'NotoSansSC',
    fontSize: 20,
    color: Colors.white,
    fontVariations: <FontVariation>[FontVariation('wght', 700)],
  );

  static const TextStyle monoStyle = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 15,
    color: Hud.dim,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('环境自检 · 字体三件套', style: titleStyle),
              const SizedBox(height: 28),
              const Text('LV.07 · EXP 1,240', style: rajdhaniStyle),
              const SizedBox(height: 20),
              const Text('宿主已绑定无限变强系统。', style: notoStyle),
              const SizedBox(height: 20),
              const Text('01:24:07 · 六维 力敏体智知魅', style: monoStyle),
              const SizedBox(height: 36),
              const Text('三套字体渲染正常 = 素材管线就绪', style: monoStyle),
            ],
          ),
        ),
      ),
    );
  }
}
