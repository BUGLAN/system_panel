# tools/fonts — 中文字体子集化

App 的中文正文字体 `NotoSansSC`（`Ref.fc`）打包的是**子集**，不是原版全字库。

| 文件 | 说明 |
|---|---|
| `src/NotoSansSC-VF.ttf` | 原版可变字体（Google Fonts，Version 2.004，wght 100–900，31036 字形，约 17MB）。**不进 App 包**，只当子集的输入 |
| `subset_noto_sc.py` | 子集脚本：生成 `app/assets/fonts/NotoSansSC-VF.ttf` 并自校验 |
| `../../app/assets/fonts/NotoSansSC-VF.ttf` | 子集产物（文件名不变，`pubspec.yaml` 不用改），约 4MB / 8835 字形 |

## 为什么要裁

原版 17MB，是安装包里最大的单个资源（2026-11-06 瘦身前 `app/assets/fonts` 共 26MB）。
App 界面文案、内置台词，加上用户输入和 LLM 日常输出的汉字，GB2312 的 6763 个常用字基本都兜得住，
多出来的两万多个字形绝大部分永远用不到。

## 子集里有什么

四块的并集（原字体里没有的码位自动忽略）：

1. **GB2312 全部字符**：用 Python 自带的 `gb2312` 编解码逐码位枚举（不下载字表），6763 个汉字 + 682 个全角符号 / 假名 / 希腊 / 西里尔 / 制表符 / 拼音
2. **ASCII** 可见字符
3. **常用标点与符号区块**：Latin-1 补充、General Punctuation、Letterlike、Number Forms、Arrows、数学运算符、带圈字母数字、制表符、几何图形、杂项符号、Dingbats、CJK Symbols and Punctuation、CJK Compatibility Forms、Halfwidth and Fullwidth Forms（具体码段见脚本 `EXTRA_BLOCKS`）
4. **`app/lib/**/*.dart` 里出现过的所有字符**（含 `\uXXXX` / `\u{...}` 转义）——界面文案与内置台词一个不漏

保留不变的东西：

- **可变轴**：`fvar` / `gvar` / `HVAR` / `avar` / `STAT` 全留，`wght` 100–900 照常可调（脚本逐字比对抽查字的默认轮廓、字宽与 gvar 变化量；首次生成时另用 `varLib.instancer` 在 100/400/700/900 四档实例化抽查，轮廓与字宽和原版逐点一致）
- **OpenType 布局特性**：`GSUB` / `GPOS` / `GDEF` 全部特性保留（`palt` `halt` `kern` `locl` `fwid` `hwid` `vert` …）
- **行高相关度量**：`hhea` / `OS/2` 不动，排版行框与原版一致
- `name` 表全部记录（fvar 命名实例、STAT 都引用它）

## 怎么重跑

在仓库根目录：

```bash
# 改了界面文案 / 台词之后先校验：报「app/lib 用到且原字体有的字」缺失就要重生成
python3 tools/fonts/subset_noto_sc.py --check

# 从 src/ 原版重新生成 + 校验
python3 tools/fonts/subset_noto_sc.py
```

- 依赖 fontTools（本机 4.25 已够用；没有就 `pip install -U fonttools -i https://mirrors.cloud.tencent.com/pypi/simple/`，全程国内源）
- 产物可复现：`recalc_timestamp = False`，同一份输入 + 同一版 fontTools 跑两次字节完全相同。换 fontTools 版本字节可能变，但字符集与校验结论不变
- 校验项：表与可变轴还在、特性没丢、字形数、界面抽查字都在、`app/lib` 用到的字全保留、GB2312 外的生僻字（`龘` U+9F98）确实被裁掉；任一项不过脚本以非 0 退出
- 想加字（比如某个常见人名用字不在 GB2312 里）：往脚本里加一个码段/字符串再重跑，别手改产物

## 缺字时会怎样

子集外的字（GB2312 以外的生僻字、人名用字、emoji、`✓` 这类原字体本来就没有的符号）**不会变豆腐块**：
Flutter 找不到字形时会按 `fontFamilyFallback` → 系统字体逐级兜底（iOS 是苹方，Android 是 Noto Sans CJK / 系统 CJK 字体），
显示出来只是字形与周围略有差异。

已知代价：

- 兜底字与 NotoSansSC 字形、字重不完全一致。`refText()` 会同时给 `fontWeight`，兜底字粗细大致跟得上；
  旧接口 `fs()`（聊天面板在用）只写 `fontVariations`，兜底字会按常规字重显示
- 用户输入或 LLM 输出里的 GBK 常见扩展字（如人名里的「堃」「喆」「珺」）会走兜底；目前判断出现频率很低，可接受
