#!/usr/bin/env bash
# ============================================================
# 宿主 SYSTEM · macOS / iOS 侧一键配置脚本
# 全程走国内源（storage.flutter-io.cn / pub.flutter-io.cn / gems.ruby-china.com）
# 明确不走 Clash 等代理：脚本会检测并拒绝带代理环境变量运行
#
# 用法（在 Mac 上）：
#   chmod +x setup-macos-ios.sh
#   ./setup-macos-ios.sh              # 装 Flutter + 环境 + 依赖 + 自检
#   FLUTTER_DIR=~/dev/flutter ./setup-macos-ios.sh   # 自定义安装目录
# ============================================================
set -euo pipefail

FLUTTER_DIR="${FLUTTER_DIR:-$HOME/development/flutter}"
PROXY_GUARD="${PROXY_GUARD:-1}"

c_ok()   { printf '\033[32m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[33m%s\033[0m\n' "$*"; }
c_err()  { printf '\033[31m%s\033[0m\n' "$*"; }
step()   { printf '\n\033[36m== %s ==\033[0m\n' "$*"; }

# ------------------------------------------------------------
step "0. 前置检查：不许挂代理 + 基本工具"
if [ "$PROXY_GUARD" = "1" ]; then
  if env | grep -qiE '^(http_proxy|https_proxy|all_proxy|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY)='; then
    c_err "检测到代理环境变量，本脚本要求直连国内源。请先执行："
    c_err "  unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY"
    exit 1
  fi
  c_ok "无代理环境变量 ✅"
fi
for t in curl python3 unzip xcode-select; do
  command -v "$t" >/dev/null 2>&1 || { c_err "缺少 $t，请先安装 Xcode Command Line Tools：xcode-select --install"; exit 1; }
done
c_ok "curl / python3 / unzip 就绪 ✅"

export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
c_ok "国内源已生效：PUB_HOSTED_URL=$PUB_HOSTED_URL"

# ------------------------------------------------------------
step "1. 解析当前 stable 版本（$FLUTTER_STORAGE_BASE_URL）"
ARCH="$(uname -m)"   # arm64 / x86_64
REL_JSON="$(curl -fsSL "$FLUTTER_STORAGE_BASE_URL/flutter_infra_release/releases/releases_macos.json")"
read -r VER URL SHA <<<"$(REL_JSON="$REL_JSON" ARCH="$ARCH" python3 - <<'PY'
import json, os
j = json.loads(os.environ["REL_JSON"])
h = j["current_release"]["stable"]
rel = next(r for r in j["releases"] if r["hash"] == h)
arch = os.environ["ARCH"]
arm = "arm64" in rel["archive"]
if (arch == "arm64") != arm:          # 兜底：按 CPU 架构挑对应包
    rel = next(r for r in j["releases"]
               if r["hash"] == h and ("arm64" in r["archive"]) == (arch == "arm64"))
print(rel["version"], j["base_url"] + "/" + rel["archive"], rel["sha256"])
PY
)"
[ -n "${VER:-}" ] || { c_err "解析版本失败（镜像可能暂时不可用）"; exit 1; }
c_ok "stable = Flutter $VER  架构 = $ARCH"

# ------------------------------------------------------------
step "2. 下载并校验 SDK"
mkdir -p "$(dirname "$FLUTTER_DIR")" "$HOME/Downloads"
ZIP="$HOME/Downloads/flutter_macos_${VER}_${ARCH}-stable.zip"
if [ -x "$FLUTTER_DIR/bin/flutter" ]; then
  c_warn "$FLUTTER_DIR 已存在 Flutter，跳过下载（要重装请先删除该目录）"
else
  curl -fL --retry 5 -C - -o "$ZIP" "$URL"
  echo "$SHA  $ZIP" | shasum -a 256 -c - || { c_err "SHA256 校验失败，删除后重来"; rm -f "$ZIP"; exit 1; }
  c_ok "SHA256 校验通过 ✅"
  step "3. 解压到 $FLUTTER_DIR"
  mkdir -p "$(dirname "$FLUTTER_DIR")"
  rm -rf "$FLUTTER_DIR"
  unzip -q "$ZIP" -d "$(dirname "$FLUTTER_DIR")"
  mv "$(dirname "$FLUTTER_DIR")/flutter" "$FLUTTER_DIR" 2>/dev/null || true
fi

# ------------------------------------------------------------
step "4. 写入 PATH 与国内源到 ~/.zshrc（幂等）"
MARK="# >>> flutter-cn (宿主 SYSTEM) >>>"
if ! grep -qF "$MARK" "$HOME/.zshrc" 2>/dev/null; then
  cat >>"$HOME/.zshrc" <<EOF

$MARK
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
export PATH="$FLUTTER_DIR/bin:\$PATH"
# <<< flutter-cn <<<
EOF
  c_ok "已追加到 ~/.zshrc（重开终端生效）"
else
  c_ok "~/.zshrc 已配置过，跳过"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

# ------------------------------------------------------------
step "5. Xcode 自检（iOS 模拟器硬前提）"
if xcode-select -p >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  c_ok "$(xcodebuild -version | head -1)"
  c_warn "如从未跑过，请执行一次：sudo xcodebuild -runFirstLaunch && sudo xcodebuild -license accept"
else
  c_err "Xcode 未就绪 —— 打开 App Store 搜索安装 Xcode（约 12~40GB），装完再跑本脚本："
  c_err "  mas install 497799835   # 若安装了 mas-cli 可直接命令行装"
  c_err "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

step "6. CocoaPods（走 ruby-china 源，不走 rubygems.org）"
if command -v pod >/dev/null 2>&1; then
  c_ok "CocoaPods $(pod --version) 已装 ✅"
else
  gem sources --remove https://rubygems.org/ 2>/dev/null || true
  gem sources --add https://gems.ruby-china.com/ 2>/dev/null || true
  gem sources -l
  sudo gem install cocoapods --no-document
fi

# ------------------------------------------------------------
step "7. Flutter 自检"
flutter --version
flutter config --no-analytics >/dev/null 2>&1 || flutter --disable-analytics >/dev/null 2>&1 || true
flutter doctor -v || true

step "8. iOS 模拟器"
xcrun simctl list devices available | sed -n '1,40p' || true
echo
c_ok "下一步：open -a Simulator  →  flutter devices  →  cd app && flutter run"
c_warn "注意：iOS 首次 pod install 会拉 CocoaPods 规格仓，若卡住执行："
c_warn "  cd ios && pod repo remove trunk && pod install"
