# 这个目录里的模型文件不入库

（见同目录的 `.gitignore` —— 模型版权红线，只在本机转换、只在本机验证。）

**所以 clone 下来之后这里只有本文件。** `pubspec.yaml` 声明了
`assets/live2d/sakiko/`，留这个文件是为了让目录存在——否则
`flutter build` 会报 "asset directory not found" 直接失败。

## 要跑起来，先本机生成模型

```bash
python tools/l2d/convert.py
```

它把 `prototype/opus-v2-dir/live2d/sakiko/`（Unity prefab）转成标准
Live2D 文件写到这里：`sakiko.model3.json` / `sakiko.moc3` /
`sakiko.physics3.json` / `textures/` / `motions/` / `expressions/`。

转换器为什么可行、以及它做过哪些验证，见 `app/STAGE-OPTIONS.md`。

## 没有模型时会怎样

不会崩：`flutter_live2d` 返回 `LOAD_FAILED`，舞台退回**全息剪影**
（原型也有同样的降级 —— 见 `docs/14`）。
