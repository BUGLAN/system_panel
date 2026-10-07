# 参考态脚本

`ref-setup.js` 用来把 `prototype/opus-v2-dir` 摆成**可复现的比对状态**。

用法（原型跑在 4925 端口）：

```powershell
cd prototype/opus-v2-dir; node server.mjs      # 另开一个终端
$js = (Get-Content tools/ref/ref-setup.js -Raw) -replace "`r`n","`n"
agent-browser --session <名字> open "http://localhost:4925"
agent-browser --session <名字> eval $js
agent-browser --session <名字> screenshot <输出路径>
```

它做四件事：

1. **`Store.veteran()`** —— 恢复原型自带的「老宿主 · 第 23 天」演示档。
   不跑这一步就会拿到被玩脏的存档（踩过：`items` 少一个键，界面印出「持有 ×undefined」；
   `S.active` 为真时底栏是「执行中」而不是「委托」）。
2. 关掉 `#boot` 覆盖层 —— 页面重载后它在等点击。
3. 隐藏 `#stage` —— 那是 WebGL 的 Live2D，Flutter 侧还没上舞台。
4. 按 `setMode()` 的类名规则摆状态（清掉板/执行/结算/失败/面板/选项/veil/环标签）。

脚本末尾是 **lobby** 那一页的摆法；换页改最后几行即可（各页的 `lineAt` 见
`js/flows.js` L23）。

## 摆每一页时会踩的坑

### 1. 清理用的内联样式会压过 `.on` 类

base 清理里写了 `el.style.opacity = 0`，那是**内联样式**——后面再加 `.on` 类也盖不过它，
元素永远不显示。重设状态时必须显式清掉：

```js
el.style.transition = 'none';
el.style.opacity = '';        // ← 清内联，让 .on 生效
el.classList.add('on');
```

（踩过：`#plateAlt` 明明 `className` 是 `on`、`children` 也有两颗，
`getComputedStyle` 却是 `opacity: 0`。）

### 2. 原型里凡是 `async` 的演出都要分步调

同步 eval 里连着写会互相覆盖。以派单板为例，玻璃落了不代表内容刻上去了：

```js
Plate.build(T); Plate.land();        // 第 1 步
// 等 2~3 秒
Plate.rankRoll(T.r);                 // 第 2 步
// 等 2~3 秒
Plate.engrave();                     // 第 3 步
// 等 2~3 秒，再补 alt / 字幕 / 截图
```

漏掉 `rankRoll` + `engrave`，截出来的板是空的（骰子还停在默认的 `F`）。

### 3. 隐藏 `#stage` 会让 `onTick` 里的定位逻辑不跑

`MainV.place()` / `Beam.place()` 这类挂在 `Stage.onTick` 上的每帧定位，
在 `Stage.onTick.length = 0` 之后不会再执行——要**手动补调一次**，
否则元素停在 `(0, -7)` 这种默认位置。

### 4. 数据也要核对，别只看区域均值

`Store.veteran(); Store.head()` 打出来逐字段对一遍。踩过：`serial` 写成 80（实为 41）、
`reason` 漏了「46 秒」——小字差异在区域均值里几乎看不出来。
Flutter 侧 `test/plate_test.dart` 有一条「数据契约」测试钉住这些值。
