import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/design/ref.dart';
import 'package:system_panel/ui/ref/ref_device.dart';

/// v3 交互层的硬约束测试。
void main() {
  testWidgets('wipe：未播放时不占画面', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              const Positioned.fill(child: ColoredBox(color: Ref.bg)),
              Positioned.fill(
                child: Builder(
                  builder: (BuildContext context) =>
                      RefWipe(title: '档案', sub: 'LOADING'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('档案'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
