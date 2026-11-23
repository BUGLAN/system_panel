/**
 * 目标类目（11 类）：名称、专属访谈卡（3 张）。
 * 由脚本从 flutter-final:app/lib/state/goal_gen.dart 逐字转出，文案一字未改。
 * 识别顺序即优先级，gen（变强）兜底必须排最后。
 */
import type { GoalCategory } from './categoryTypes';

export const CATEGORIES: readonly GoalCategory[] = [
  {
    id: 'run',
    label: '奔跑',
    cards: [
      { id: 'run.now', question: '现在能跑多远？', options: ['3 公里以内', '3~5 公里', '5 公里以上', '没跑过'] },
      { id: 'run.freq', question: '一周跑几次？', options: ['1~2 次', '3~4 次', '5 次以上', '不一定'] },
      { id: 'run.slot', question: '愿意每周留几个跑步时段？', options: ['2 个', '3~4 个', '5 个以上'] },
    ],
  },
  {
    id: 'slim',
    label: '轻盈',
    cards: [
      { id: 'slim.target', question: '想先减下多少？', options: ['2~3 斤', '5 斤左右', '10 斤以上', '没称过，先记录'] },
      { id: 'slim.diet', question: '最近吃得怎么样？', options: ['三餐规律', '经常外卖', '宵夜不断'] },
      { id: 'slim.move', question: '现在动多少？', options: ['基本不动', '偶尔走走', '每周有运动习惯'] },
    ],
  },
  {
    id: 'fit',
    label: '力量',
    cards: [
      { id: 'fit.base', question: '现在能做几个俯卧撑？', options: ['一个都费劲', '10 个以内', '20 个以上'] },
      { id: 'fit.freq', question: '一周想练几次？', options: ['1~2 次', '3~4 次', '5 次以上'] },
      { id: 'fit.place', question: '在哪练？', options: ['家里徒手', '健身房', '都行'] },
    ],
  },
  {
    id: 'lang',
    label: '开口',
    cards: [
      { id: 'lang.level', question: '现在什么水平？', options: ['零基础', '能读不能说', '口语还行，想进阶'] },
      { id: 'lang.exam', question: '有没有考试目标？', options: ['四六级', '雅思托福', '没有，纯兴趣'] },
      { id: 'lang.daily', question: '每天能背多少词？', options: ['20 个', '50 个', '量翻倍也要冲'] },
    ],
  },
  {
    id: 'exam',
    label: '上岸',
    cards: [
      { id: 'exam.stage', question: '备考到什么阶段了？', options: ['刚开始', '过了一半', '快考试了'] },
      { id: 'exam.hours', question: '现在每天学多久？', options: ['1 小时以内', '2~3 小时', '4 小时以上'] },
      { id: 'exam.weak', question: '最弱的是哪块？', options: ['专业课', '英语', '政治 / 公共课'] },
    ],
  },
  {
    id: 'sleep',
    label: '早起',
    cards: [
      { id: 'sleep.schedule', question: '现在几点起、几点睡？', options: ['0 点前睡 7 点前起', '0-1 点睡 8 点起', '1-2 点睡 9 点后起', '没有固定'] },
      { id: 'sleep.recent', question: '最近几天作息如何？', options: ['基本规律', '偶尔熬夜', '天天熬夜'] },
      { id: 'sleep.persist', question: '愿意做怎样的坚持？', options: ['每天早睡 15 分钟', '固定起床闹钟', '午休不超 30 分钟', '睡前不碰手机'] },
    ],
  },
  {
    id: 'skill',
    label: '练技能',
    cards: [
      { id: 'skill.level', question: '现在什么水平？', options: ['零基础', '学过一点又放下了', '能独立练完一段'] },
      { id: 'skill.freq', question: '一周能练几次？', options: ['1~2 次', '3~4 次', '几乎每天'] },
      { id: 'skill.first', question: '想先练会什么？', options: ['把基本功练扎实', '完整练会一首 / 一段', '能当众露一手'] },
    ],
  },
  {
    id: 'make',
    label: '作品',
    cards: [
      { id: 'make.level', question: '现在是什么水平？', options: ['纯新手', '会一点', '有作品'] },
      { id: 'make.freq', question: '一周能创作几次？', options: ['1~2 次', '3~4 次', '几乎每天'] },
      { id: 'make.first', question: '想先做出什么？', options: ['一件完整小作品', '先养成日常习惯', '能给人看'] },
    ],
  },
  {
    id: 'code',
    label: '上线',
    cards: [
      { id: 'code.level', question: '现在什么水平？', options: ['刚入门', '能写小项目', '想提升架构'] },
      { id: 'code.dir', question: '想往哪个方向走？', options: ['算法刷题', '做一个完整项目', '找工作备战'] },
      { id: 'code.daily', question: '每天能投入多久？', options: ['30 分钟', '1~2 小时', '3 小时以上'] },
    ],
  },
  {
    id: 'bold',
    label: '自信',
    cards: [
      { id: 'bold.scene', question: '最想突破哪个场景？', options: ['当众讲话', '主动搭话', '线上表达'] },
      { id: 'bold.now', question: '现在什么状态？', options: ['能躲就躲', '硬着头皮上', '还行，想更强'] },
      { id: 'bold.step', question: '愿意从多小的一步开始？', options: ['打招呼就行', '主动开口一次', '直接挑战演讲'] },
    ],
  },
  {
    id: 'gen',
    label: '变强',
    cards: [
      { id: 'gen.area', question: '最想在哪个方面变强？', options: ['身体', '头脑', '习惯', '收入'] },
      { id: 'gen.time', question: '现在每天能自由支配多久？', options: ['30 分钟', '1~2 小时', '3 小时以上'] },
      { id: 'gen.first', question: '愿意先从哪件小事开始？', options: ['每天固定 20 分钟', '一周试 3 次', '先做一次看看'] },
    ],
  },
];
