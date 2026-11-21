import type { AttrMap } from './attrs';
import type { Rank } from './rank';

/** 一张访谈卡：一个问题 + 3~4 个现成选项（「自己写」由组件兜底） */
export interface InterviewCard {
  /** 卡 id（答案映射的键，如 run.now） */
  id: string;
  question: string;
  options: readonly string[];
}

/** 日常任务模板 */
export interface DailyTemplate {
  title: string;
  proof: string;
  minutes: number;
  attrs: AttrMap;
  rank: Rank;
  /** false = 打卡单（整天型：早睡、喝水……不计时、当天内随时交）；缺省 = 计时单 */
  timed?: boolean;
}

/** 目标类目 */
export interface GoalCategory {
  id: string;
  label: string;
  /** 六维倾向（运动类主属性是「力」= 体质；习惯类给「体」= 意志） */
  tilt: AttrMap;
  /** 专属访谈卡（3 张） */
  cards: readonly InterviewCard[];
  /** 专属日常池 */
  daily: readonly DailyTemplate[];
}
