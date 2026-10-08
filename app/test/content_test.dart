import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/data/content.dart';

/// 文案表的结构性约束。
///
/// 为什么单独立这个：`[[…]]` 高亮（`util.js` `richChars()` → `<em>`：青色 +
/// 字重 650 + 辉光）**丢掉了肉眼不容易发现** —— 那只是几个字变了个颜色，
/// 而我当初把这几句写死在 `main.dart` 里时，四处高亮**全丢了**，
/// 220 条测试一条都没拦住。
///
/// 这条测试专门盯它：原型里带高亮的句子，这里也必须带，而且括号要成对。
void main() {
  /// `[[…]]` 成对且非空
  void checkHighlighted(String label, String s) {
    const String open = '[[';
    const String close = ']]';
    int a = 0, b = 0;
    for (int i = 0; i + 1 < s.length; i++) {
      if (s.substring(i, i + 2) == open) a++;
      if (s.substring(i, i + 2) == close) b++;
    }
    expect(a, 1, reason: '$label 应该恰好有一个 [[ 高亮起点：$s');
    expect(b, 1, reason: '$label 应该恰好有一个 ]] 高亮终点：$s');
    final int i0 = s.indexOf(open), i1 = s.indexOf(close);
    expect(i1, greaterThan(i0 + 2), reason: '$label 的高亮内容不能是空的：$s');
  }

  group('页面字幕的高亮（content.js 里这几句都带 [[…]]）', () {
    test('大厅 holding', () => checkHighlighted('holding', LINES.holding));

    test('绑定仪式 askGoal', () => checkHighlighted('askGoal', LINES.askGoal));

    test('主线全景 mainline', () {
      checkHighlighted('mainline', LINES.mainline(3, 8));
      // `{d}/{n}` 两个数都在高亮里
      expect(LINES.mainline(3, 8), contains('[[3/8]]'));
    });

    test('认输补救 remedyLine', () {
      checkHighlighted('remedyLine', LINES.remedyLine);
      expect(LINES.remedyLine, contains('[[{dl}]]'));
    });
  });

  group('其余带高亮的句子（早先就有的，一并钉住）', () {
    test('execNear 剩不到 3 分钟', () {
      checkHighlighted('execNear', LINES.execNear);
    });

    test('回来的那几句', () {
      checkHighlighted('back2h', LINES.back2h);
      checkHighlighted('back12h', LINES.back12h);
      checkHighlighted('backLong', LINES.backLong);
      // back10m / back36h 原型里就没有高亮
      expect(LINES.back10m, isNot(contains('[[')));
      expect(LINES.back36h, isNot(contains('[[')));
    });

    test('道具台词', () {
      // content.js L358-360 三句都没有高亮
      for (final String s in <String>[
        LINES.itemDbl,
        LINES.itemCrit,
        LINES.itemShield,
      ]) {
        expect(s, isNot(contains('[[')));
      }
    });
  });

  group('默认停顿（原型 `clamp(420 + plain(text).length * 42, 900, 2400)`）', () {
    test('短句夹到 900', () {
      // 5 字 → 420+210 = 630 → 900
      expect(LINES.defaultHold('一二三四五'), 900);
    });

    test('中等长度按字数算', () {
      // 20 字 → 420+840 = 1260
      expect(LINES.defaultHold('一二三四五六七八九十' * 2), 1260);
    });

    test('长句夹到 2400', () {
      // 60 字 → 420+2520 = 2940 → 2400
      expect(LINES.defaultHold('一' * 60), 2400);
    });

    test('⚠️ 高亮标记不计入字数（原型走的是 plain(text)）', () {
      // 注意：中间那个空格也算一个码元 —— 原型用的是 JS 的 .length，不是"字数"
      const String plain = '我手里有 4 单。都是给你的。'; // 15 个码元
      const String marked = '我手里有 [[4]] 单。都是给你的。'; // 带标记，多 4 个
      expect(LINES.defaultHold(marked), LINES.defaultHold(plain));
      expect(LINES.defaultHold(plain), 420 + 15 * 42);
    });

    test('回来的那几句真的落在原型范围内', () {
      for (final String s in <String>[
        LINES.back10m,
        LINES.back2h,
        LINES.back12h,
        LINES.back36h,
        LINES.backLong,
      ]) {
        final int h = LINES.defaultHold(s);
        expect(h, greaterThanOrEqualTo(900));
        expect(h, lessThanOrEqualTo(2400));
      }
    });
  });
}
