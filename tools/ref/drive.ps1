# 全量抓图驱动（Windows / PowerShell + adb）
#
# 把"抓 13 张比对图"要点的坐标固化下来 —— 之前这些都散在每轮的临时命令里，
# 换一轮就得重新推一遍坐标（我为此点错过好几次：收起键点到了屏幕外、
# 面板的 ✕ 点到了 HUD 上）。
#
# 用法：
#   pwsh -File tools/ref/drive.ps1            # 抓全部
#   pwsh -File tools/ref/drive.ps1 -Only lobby,plate
#
# 抓完跑 `python tools/ref/regress.py` 出总表。

param(
    [string]$Serial = "emulator-5554",
    [string]$Only = "",
    [string]$Out = "E:\repo\system_panel\.verify"
)

$ErrorActionPreference = "Stop"
$PKG = "com.systempanel.app"

function Sh([string]$cmd) { adb -s $Serial shell $cmd | Out-Null }
function Tap([int]$x, [int]$y) { Sh "input tap $x $y" }
function Hold([int]$x, [int]$y, [int]$ms) { Sh "input swipe $x $y $x $y $ms" }
function Shot([string]$name) {
    Sh "screencap -p /sdcard/_cap.png"
    adb -s $Serial pull /sdcard/_cap.png "$Out\$name" | Out-Null
    Write-Host "  -> $name"
}
function Sleep([double]$s) { Start-Sleep -Milliseconds ([int]($s * 1000)) }

function Restart([double]$wait = 12) {
    Sh "am force-stop $PKG"
    Sleep 2
    Sh "am start -n $PKG/.MainActivity"
    Sleep $wait
}

$want = if ($Only) { $Only -split "," } else { @(
    "boot","lobby","system","archive","supply","plate","exec","result",
    "fail","mainv","rings","onboard","banner") }

# 坐标（物理像素 = 逻辑 × 2，390×844 @2x）
$WAKE     = @(390, 800)
$MENU     = @(714, 70)
$SH_X     = @(712, 712)      # 投影面板右上角 ✕（logical 356,356）
$DOCK_MAIN = @(94, 1542)
$DOCK_ARC  = @(218, 1542)
$DOCK_SUP  = @(346, 1542)
$CTA      = @(640, 1528)
$FP       = @(390, 1452)     # 指纹（长按 1.5s）
$SUBMIT   = @(390, 1452)
$QUIT     = @(138, 1596)     # 认输（长按 1.5s）
$WIPE     = @(660, 1410)     # 系统面板「按住 2 秒」—— ⚠️ t9 加 LLM·视觉校验组后，
                              # 重置存档被压到折叠线以下：必须先滚到底再按（见 onboard 流程）
$PRESET3  = @(598, 1348)     # 第三个目标预设
$ASK_OK   = @(664, 1566)

Restart

if ($want -contains "boot") { Write-Host "[boot]"; Shot "flutter-step1-boot.png" }

# 大厅
Tap $WAKE[0] $WAKE[1]; Sleep 7
if ($want -contains "lobby") { Write-Host "[lobby]"; Shot "flutter-step2-lobby.png" }
if ($want -contains "rings") { Write-Host "[rings]"; Shot "flutter-step16-rings.png" }

# 系统面板
Tap $MENU[0] $MENU[1]; Sleep 2
if ($want -contains "system") { Write-Host "[system]"; Shot "flutter-step8-system.png" }
# 档案
Tap $SH_X[0] $SH_X[1]; Sleep 1.5
Tap $DOCK_ARC[0] $DOCK_ARC[1]; Sleep 2
if ($want -contains "archive") { Write-Host "[archive]"; Shot "flutter-step7-sheet.png" }
# 补给
Tap $SH_X[0] $SH_X[1]; Sleep 1.5
Tap $DOCK_SUP[0] $DOCK_SUP[1]; Sleep 2
if ($want -contains "supply") { Write-Host "[supply]"; Shot "flutter-step8-supply.png" }
Tap $SH_X[0] $SH_X[1]; Sleep 1.5

# 派单板（等揭晓仪式演完）
Tap $CTA[0] $CTA[1]; Sleep 6
if ($want -contains "plate") { Write-Host "[plate]"; Shot "flutter-step3-plate.png" }

# 执行（长按指纹接单）
Hold $FP[0] $FP[1] 1500; Sleep 3
if ($want -contains "exec") { Write-Host "[exec]"; Shot "flutter-step4-exec.png" }

# 结算
Tap $SUBMIT[0] $SUBMIT[1]; Sleep 8
if ($want -contains "result") { Write-Host "[result]"; Shot "flutter-step5-result.png" }

# 主线全景：⚠️ 结算页上**没有底栏**，必须先回到大厅再点 dock。
#    （第一版脚本直接从结算页点 dock，点空了，抓到的还是结算页 —— 回归表里 13.4%）
if ($want -contains "mainv") {
    Write-Host "[mainv]"
    Restart
    Tap $WAKE[0] $WAKE[1]; Sleep 5
    Tap $DOCK_MAIN[0] $DOCK_MAIN[1]; Sleep 3
    Shot "flutter-step10-mainv.png"
}

# 失败：重来一遍到执行页，再认输
if ($want -contains "fail") {
    Write-Host "[fail]"
    Restart
    Tap $WAKE[0] $WAKE[1]; Sleep 5
    Tap $CTA[0] $CTA[1]; Sleep 6
    Hold $FP[0] $FP[1] 1500; Sleep 3
    Hold $QUIT[0] $QUIT[1] 1500; Sleep 5
    Shot "flutter-step6-fail.png"
}

# 绑定仪式 + 横幅：清档 → 系统面板里长按重置
if (($want -contains "onboard") -or ($want -contains "banner")) {
    Write-Host "[onboard]"
    Sh "pm clear $PKG"
    # ⚠️ `pm clear` 之后开机自检更慢（要重建存档），12s 不够 —— 会抓到「触碰屏幕 · 唤醒系统」
    #    那一屏，然后被当成"回归"（4.8%）。给足 18s 再唤醒。
    Sh "am start -n $PKG/.MainActivity"; Sleep 18
    Tap $WAKE[0] $WAKE[1]; Sleep 6
    Tap $MENU[0] $MENU[1]; Sleep 2
    # ⚠️ t9 在系统页加了 LLM·视觉校验组（开关+BaseURL+Key+模型名+测试连接），
    #    把「重置存档 · 按住 2 秒」压到折叠线以下 —— 旧坐标 (659,1282) 按空。
    #    滚到底（四屏，留足回弹余量），重置行稳定落在 (660,1410~1420)；
    #    按两次（幂等：第一下若没按中，第二下补上；已重置则落在目标输入区，无害）。
    Sh "input swipe 390 1300 390 400 600"; Sleep 0.9
    Sh "input swipe 390 1300 390 400 600"; Sleep 0.9
    Sh "input swipe 390 1300 390 400 600"; Sleep 0.9
    Sh "input swipe 390 1300 390 400 600"; Sleep 1
    Hold $WIPE[0] $WIPE[1] 2400; Sleep 2.5
    Hold $WIPE[0] $WIPE[1] 2400; Sleep 2.5
    if ($want -contains "onboard") { Shot "flutter-step13-onboard.png" }
    if ($want -contains "banner") {
        # ⚠️ t6 改了绑定流：确定 → 5 张访谈卡 → 生成三天计划 → 回大厅才弹「见面礼」横幅。
        #    逐卡点「中间 chip + 前进」，等生成后抓 2200ms 的横幅窗口。
        Tap $PRESET3[0] $PRESET3[1]; Sleep 1
        Tap $ASK_OK[0] $ASK_OK[1]; Sleep 1.5
        for ($i = 0; $i -lt 5; $i++) {
            Tap 364 1375          # 访谈卡 chip 行（高卡位）
            Sleep 0.7
            Tap 364 1475          # chip 行（低卡位 —— 卡高随题面浮动，两行都点兜底）
            Sleep 0.9
        }
        Sleep 2                   # 生成三天计划 → 回大厅，横幅窗口 2200ms
        Shot "flutter-step13b-banner.png"
    }
}

Write-Host "抓图完成 -> $Out"
