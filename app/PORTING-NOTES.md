# CSS → Flutter 移植约定

> 这份是复刻 `prototype/opus-v2-dir` 过程中**踩出来的**差异清单，不是猜的：
> 每一条都对应一次真实的像素偏差，括号里是当时的差值。
> 新一页动手前先扫一遍，能省掉大半返工。

## 一、盒子模型

### 1. `Border` 占布局，CSS 的 `inset box-shadow` 不占
原型用 `box-shadow: inset 0 0 0 1px X` 画描边的地方，Flutter 里若写成 `Border.all`，
描边会**挤进内容盒**：胶囊宽 2px、卡内内容右移 1px。

**做法**：`Border` 保留（视觉位置一致），但 padding 各减掉描边宽度。
已用到：HUD 金币、执行面板道具/认输、派单板 alt、结算卡/保存键/筹码、
商店行、分段开关、按住重置键。

> 商店行漏减 1px 的后果最典型：每行高 1px，四行累积到第 4 行**低了 8px**，
> 四个价格键全错位（-17.3）。

### 2. `Stack` 默认 `clipBehavior: hardEdge`
CSS 里没设 `overflow` 的元素，探到容器外的装饰（辉光、阴影）会照常绘制；
Flutter 的 `Stack` 会**裁掉**。面板顶边那道光往上 30px 的辉光就是这么丢的（-10.0）。

### 3. `Container` 默认不裁
反过来，CSS 有 `overflow: hidden` 的地方（如结算经验条）Flutter 必须显式
`clipBehavior: Clip.antiAlias`，否则子元素的 `boxShadow` 会漏到外面一行（+5.3）。

## 二、装饰

### 4. `boxShadow` 会透进透明的内部
CSS 的外阴影只画在 border-box **外面**；Flutter 的 `BoxShadow` 是「在背后画一个模糊的
填充形状」——**组件内部若是透明的，阴影会整块透上来**。

**症状**：带外发光的透明圆环内部被点亮（大字环 +30.7、商店圆字标 +13.3）。
**做法**：改用 `CustomPainter` 画一个**描边的模糊圆**（只往外散）。

### 5. `RadialGradient` 做「内辉光」不可控
`inset 0 0 40px <color>` 的内辉光，用 `RadialGradient` 会被渲染成整块底都被点亮
（内部亮度 92 vs 原型 35）。

**做法**：显式 `ui.Gradient.radial` + 三段 stop，按实测衰减曲线压窄；
注意 CSS 的 inset 阴影**在边缘只有约一半强度**、衰减很快（距边缘 8px 处原型只加 ~6 亮度）。

### 6. CSS 的椭圆 `radial-gradient` 要手动压扁
Flutter 的 `Gradient.radial` 是正圆。做法：
```dart
canvas.save();
canvas.translate(c.dx, c.dy); canvas.scale(1, ry / rx); canvas.translate(-c.dx, -c.dy);
canvas.drawCircle(c, rx, paint);
canvas.restore();
```

## 三、文字

### 7. `TextStyle.height` 不写会继承 Material 的 1.43
每个字体家族都有自己的 `line-height: normal`，写进 `design/tokens.dart` 的
`kNormalLineHeight`，并且 `leadingDistribution: TextLeadingDistribution.even`。
另外 **CSS 没写 `line-height` 的地方不要传 `height: 1`**（会让这一行矮一截，级联出去）。

### 8. inline 元素的「行框下沉」
CSS 里 `<span>` 这类 inline 元素被父级 16px 的 strut 撑出的行框里会下沉 5~6px
（`.sh-k`、`.rs-head .kick`、`.fv-remedy .kick` 都是）。
做法：固定高度的槽 + 等量 `Padding(top:)`，别指望默认居中。

### 9. 可变字体必须用 `fontVariations`
`FontVariation('wght', N)` / `FontVariation('wdth', N)`；光写 `fontWeight` 不生效。

### 10. 已知不可消除的残差：文字墨量
Flutter-on-Android 在相同字体/字号/字重下只有 Chrome-on-Windows 的 **63%~83%** 墨量。
已验证不是降采样造成的、不是字重映射错了——是光栅化差异。
**不要靠改字重去「凑」**，那是在伪造。

## 四、层级

### 11. 原型的 z 序不能想当然
`#veil` 是 z-auto（在 `#ui` 之后绘制），而 `.line` z=3、`#choices` z=4、`#plateAlt` z=2
——所以认输时 veil 压得住 `#failv`，压不住字幕和选项。
**Stack 的先后顺序必须照 CSS 的 z 序排**（放错主按钮区域差 -81.7）。

### 12. 透明度为 0 的组件照样吃点击
`AnimatedOpacity` 收起后**仍然参与命中测试**：收起的回应按钮压在派单板指纹上，
把「按住 · 接下」整个吃掉了。
**做法**：所有会收起的浮层都套 `IgnorePointer(ignoring: !visible)`。

## 五、测试

### 13. `setSurfaceSize` 不改 `MediaQuery`
它只改布局约束，`MediaQuery.sizeOf()` 仍报默认的 800×600。
**按百分比定位**的组件（`top: 38%` 这种）必须用：
```dart
tester.view.physicalSize = const Size(390 * 3, 844 * 3);
tester.view.devicePixelRatio = 3.0;
addTearDown(tester.view.reset);
```

### 14. `flutter test` 的占位字体每字形 1em 宽
凡「宽度/高度由文字撑出来」的盒子都量不准，只断言与文字无关的坐标
（左右边、固定尺寸、比例）。
`Text.rich` 用 `find.textContaining`，`find.text` 匹配不到。

### 15. `FractionallySizedBox` 少了 `heightFactor` 会量成 0 高
没有子元素的 `DecoratedBox` 在松高度约束下高度为 0——开机屏进度条和执行面板
时限条**一直是空的**，我一度把差异误判成 box-shadow 衰减。断言填充高度能钉住它。

## 六、参考态（比对方法本身）

### 16. 参考态必须可复现
原型的存档在浏览器里，随手点几下就脏了。
**每次比对前先跑 `.verify/ref-setup.js`**：`Store.veteran()` 恢复演示档 + 关掉 `#boot`
覆盖层 + 隐藏 `#stage`（Flutter 侧还没上舞台）。

踩过的坑：脏存档的 `items` 少一个键，界面上印出「持有 ×undefined」，
被我误判成原型的数据 bug；`S.active` 为真时底栏是「执行中」而不是「委托」。

### 17. 参考态本身也要校验
手工重建 DOM 时漏一个类（比如 `soft`），就会拿「非 soft 的参考」去比
「soft 的实现」，字幕正文差 -22 全记在 Flutter 头上。

### 18. 动画中的元素不能量
`.line` 有 `transition: top .5s`，`.rs-glyph` 有 `slam .7s`（从 scale 2.4 起）
——量到的是中间态。设完状态**等 1~2 秒再量**。

**更隐蔽的一种：清掉 `Stage.onTick` 会把每帧驱动的 transform 冻在半截。**
执行面板那只眼睛 `.eye` 的 CSS 是 `width:16px; height:9px`，但原型在 `#exEye` 上挂了
一个 `transform: scaleY(.7)` 的眨眼/口型动画。我清空 onTick 后量到它高 6.3px，
**误以为是「Chrome 把 inset 环渲染得更扁」**，于是把 Flutter 侧也画扁了 —— 追着
一个不存在的浏览器怪癖跑了一整轮。

正确做法：**摆参考态时把这些每帧驱动的 transform 显式归位**
（`el.style.transform = 'none'`），再截图比对。
