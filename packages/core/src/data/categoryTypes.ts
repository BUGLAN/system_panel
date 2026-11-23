/** 一张访谈卡：一个问题 + 3~4 个现成选项（「自己写」由组件兜底） */
export interface InterviewCard {
  /** 卡 id（答案映射的键，如 run.now） */
  id: string;
  question: string;
  options: readonly string[];
}

/** 目标类目 */
export interface GoalCategory {
  id: string;
  label: string;
  /** 专属访谈卡（3 张） */
  cards: readonly InterviewCard[];
}
