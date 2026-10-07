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
