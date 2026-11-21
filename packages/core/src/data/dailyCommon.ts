/**
 * 通用日常池（30 条）：任何主线的日常都从这里补位。
 * 由脚本从 flutter-final:app/lib/state/goal_gen.dart 的 kDailyCommon 逐字转出。
 * timed: false = 打卡单（整天型，docs/50 D3.3）。
 */
import type { DailyTemplate } from './categoryTypes';

export const DAILY_COMMON: readonly DailyTemplate[] = [
  { title: '整理桌面，只留今天要用的东西', proof: '桌面照片', minutes: 10, attrs: { 知: 1 }, rank: 'F' },
  { title: '出门走 3000 步', proof: '步数截图', minutes: 30, attrs: { 体: 1, 敏: 1 }, rank: 'E' },
  { title: '读 20 页书', proof: '页码照片', minutes: 30, attrs: { 智: 1, 知: 1 }, rank: 'E' },
  { title: '发呆 10 分钟，不碰手机', proof: '计时截图', minutes: 12, attrs: { 知: 2 }, rank: 'F' },
  { title: '给一个很久没联系的人发条消息', proof: '对话截图（可打码）', minutes: 8, attrs: { 魅: 2 }, rank: 'E' },
  { title: '20 个深蹲', proof: '自拍或计数截图', minutes: 6, attrs: { 力: 1, 体: 1 }, rank: 'F' },
  { title: '把一件拖了一周的小事做完', proof: '完成截图', minutes: 25, attrs: { 知: 1, 智: 1 }, rank: 'D' },
  { title: '拉伸 10 分钟', proof: '拉伸照片', minutes: 12, attrs: { 敏: 2 }, rank: 'F' },
  { title: '平板支撑累计 3 分钟', proof: '计时截图', minutes: 10, attrs: { 力: 1, 体: 1 }, rank: 'E' },
  { title: '写 300 字，写什么都行', proof: '文字截图', minutes: 25, attrs: { 智: 1, 魅: 1 }, rank: 'E' },
  { title: '收拾房间的一个角落', proof: '前后对比照片', minutes: 15, attrs: { 知: 1, 体: 1 }, rank: 'F' },
  { title: '跳绳 500 下', proof: '计数截图', minutes: 12, attrs: { 敏: 1, 体: 1 }, rank: 'E' },
  { title: '学一个新技巧，今天用三次', proof: '截图', minutes: 15, attrs: { 智: 1, 敏: 1 }, rank: 'F' },
  { title: '做一顿饭', proof: '饭菜照片', minutes: 40, attrs: { 体: 1, 知: 1 }, rank: 'D' },
  { title: '早起后喝一杯水，再做 10 个开合跳', proof: '计时截图', minutes: 5, attrs: { 体: 1, 力: 1 }, rank: 'F' },
  { title: '把手机放到够不着的地方，专注 25 分钟', proof: '计时截图', minutes: 30, attrs: { 智: 1, 知: 1 }, rank: 'E' },
  { title: '走楼梯不坐电梯，上下各两趟', proof: '步数截图', minutes: 10, attrs: { 体: 1, 敏: 1 }, rank: 'F' },
  { title: '写三行今天想说的话，写完就合上', proof: '文字截图', minutes: 10, attrs: { 魅: 1, 知: 1 }, rank: 'F' },
  { title: '洗一次碗，顺便把台面擦干净', proof: '前后对比照片', minutes: 15, attrs: { 知: 1, 体: 1 }, rank: 'F' },
  { title: '靠墙静蹲 3 组，每组 45 秒', proof: '计时截图', minutes: 8, attrs: { 力: 1, 体: 1 }, rank: 'E' },
  { title: '把明天的三件事写下来，只写三件', proof: '清单照片', minutes: 10, attrs: { 知: 1, 智: 1 }, rank: 'F' },
  { title: '念一段 3 分钟的文字，念出声', proof: '录音截图', minutes: 10, attrs: { 魅: 1, 智: 1 }, rank: 'F' },
  { title: '整理一次手机相册，删掉 30 张废片', proof: '相册截图', minutes: 15, attrs: { 知: 1 }, rank: 'F' },
  { title: '靠墙站直 10 分钟，别塌肩', proof: '计时截图', minutes: 10, attrs: { 魅: 1, 体: 1 }, rank: 'F' },
  { title: '喝水 6 杯，拿杯子凑数不算', proof: '杯子照片', minutes: 5, attrs: { 体: 1 }, rank: 'F', timed: false },
  { title: '把昨天没做完的那件事补完', proof: '完成截图', minutes: 30, attrs: { 知: 1, 智: 1 }, rank: 'D' },
  { title: '快走 20 分钟，不许边刷手机边走', proof: '步数截图', minutes: 25, attrs: { 体: 1, 敏: 1 }, rank: 'E' },
  { title: '手写一页字，慢一点，写整齐', proof: '纸面照片', minutes: 15, attrs: { 敏: 1, 知: 1 }, rank: 'F' },
  { title: '今天不喝含糖饮料，一杯都不', proof: '晚上拍一张今天喝过的东西', minutes: 5, attrs: { 知: 1, 体: 1 }, rank: 'F', timed: false },
  { title: '睡前 10 分钟回顾今天，想清楚一件做对的事', proof: '笔记照片', minutes: 12, attrs: { 知: 1, 魅: 1 }, rank: 'F' },
];
