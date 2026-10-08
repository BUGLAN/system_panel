/// 内联 SVG 素材 —— 原样搬自 prototype/opus-v2-dir/index.html 的 `<svg>`，
/// 颜色/线宽写死进属性，省掉 flutter_svg 的 colorFilter（那会把整张图一起染色）。
library;

/// HUD 金币（ui.js L10 COIN_SVG + app.css L111）
const String kIconCoin =
    '<svg viewBox="0 0 16 16"><g fill="none" stroke="#38E1FF" stroke-width="1.6">'
    '<path d="M8 1l6 3.5v7L8 15l-6-3.5v-7z"/></g></svg>';

/// .buy 里的金币（同 COIN_SVG，但 stroke 走 var(--deep)、线宽 2；买不起时变灰）
const String kIconCoinDark =
    '<svg viewBox="0 0 16 16"><g fill="none" stroke="#021022" stroke-width="2" stroke-linejoin="miter" stroke-miterlimit="10">'
    '<path d="M8 1l6 3.5v7L8 15l-6-3.5v-7z"/></g></svg>';

const String kIconCoinMuted =
    '<svg viewBox="0 0 16 16"><g fill="none" stroke="#4F607B" stroke-width="2" stroke-linejoin="miter" stroke-miterlimit="10">'
    '<path d="M8 1l6 3.5v7L8 15l-6-3.5v-7z"/></g></svg>';

/// 底栏三颗（index.html L55-57 + app.css L215）
const String kIconMain =
    '<svg viewBox="0 0 24 24"><g fill="none" stroke="#E9FBFF" stroke-width="1.3">'
    '<ellipse cx="12" cy="7" rx="6" ry="1.8"/>'
    '<ellipse cx="12" cy="12" rx="8" ry="2.4"/>'
    '<ellipse cx="12" cy="17.5" rx="9" ry="2.8"/></g></svg>';

const String kIconArchive =
    '<svg viewBox="0 0 24 24"><g fill="none" stroke="#E9FBFF" stroke-width="1.3">'
    '<path d="M12 3l7.8 4.5v9L12 21l-7.8-4.5v-9z"/>'
    '<path d="M12 8l3.5 2v4L12 16l-3.5-2v-4z"/></g></svg>';

const String kIconSupply =
    '<svg viewBox="0 0 24 24"><g fill="none" stroke="#E9FBFF" stroke-width="1.3">'
    '<rect x="4" y="8" width="16" height="11" rx="1"/>'
    '<path d="M8 8V6a4 4 0 0 1 8 0v2M4 12h16"/></g></svg>';

/// 结算右上角「保存战报」的下载箭头（ui.js `ResultUI.build`）
const String kIconDownload =
    '<svg viewBox="0 0 16 16"><g fill="none" stroke="#38E1FF" stroke-width="1.6" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M8 2v8M4.5 6.5L8 10l3.5-3.5M2.5 13.5h11"/></g></svg>';

/// 「对话」入口（docs/18 §2.6 新增；对话气泡 + 两点，同 HUD/底栏的线宽语言）
const String kIconChat =
    '<svg viewBox="0 0 24 24"><g fill="none" stroke="#38E1FF" stroke-width="1.5" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M4 6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5v8a2.5 2.5 0 0 1-2.5 2.5H10l-4.2 3.4c-.5.4-1.3 0-1.3-.7V6.5z"/>'
    '<circle cx="8.6" cy="10.5" r="0.9" fill="#38E1FF" stroke="none"/>'
    '<circle cx="12" cy="10.5" r="0.9" fill="#38E1FF" stroke="none"/>'
    '<circle cx="15.4" cy="10.5" r="0.9" fill="#38E1FF" stroke="none"/></g></svg>';
