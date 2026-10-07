/// 时间/数字格式 —— 真源：prototype/opus-v2-dir/js/util.js
library;

/// `fmtClock`（util.js L46）：1 小时以内是 `MM:SS`，超过是 `H:MM:SS`
String fmtClock(Duration d) {
  final int s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final int h = s ~/ 3600;
  final int m = (s % 3600) ~/ 60;
  final int ss = s % 60;
  final String mm = h > 0
      ? m.toString().padLeft(2, '0')
      : m.toString().padLeft(2, '0');
  return '${h > 0 ? '$h:' : ''}$mm:${ss.toString().padLeft(2, '0')}';
}

/// `fmtMin`（util.js L51）
String fmtMin(int min) {
  if (min < 60) return '$min 分钟';
  if (min % 60 != 0) return '${min ~/ 60} 小时 ${min % 60} 分';
  return '${min ~/ 60} 小时';
}

/// `fmtDur`（util.js L37）—— 一段时长：秒 → 分 → 小时 → 天
String fmtDur(Duration d) {
  final int s = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (s < 60) return '$s 秒';
  final int m = s ~/ 60;
  if (m < 60) return s % 60 != 0 ? '$m 分 ${s % 60} 秒' : '$m 分';
  final int h = m ~/ 60;
  if (h < 48) return m % 60 != 0 ? '$h 小时 ${m % 60} 分' : '$h 小时';
  return '${h ~/ 24} 天';
}
