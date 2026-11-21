/**
 * 拆解失败卡的文案（B1：按失败类型给标题和她那句）。前端失败卡与服务端共用。
 */
import type { PlanFailureCode } from './planFailure';

export function planFailTitle(c: PlanFailureCode): string {
  switch (c) {
    case 'noKey':
      return '还没配 Key';
    case 'noConsent':
      return '还没同意告知';
    case 'network':
      return '网络断了';
    case 'cors':
      return '浏览器拦了跨域';
    case 'timeout':
      return '等太久了';
    case 'httpError':
      return '上游不可用';
    case 'badGoal':
      return '这个目标她不接';
    case 'quota':
      return '今天额度用完了';
    default:
      return '这次没拆明白';
  }
}

/** 失败时她那句（答案都在 —— 重试不用重答） */
export function planFailLine(c: PlanFailureCode): string {
  switch (c) {
    case 'noKey':
      return '脑子（Key）还没装上。去设置里填好，或者先跳过，目标我记着。';
    case 'noConsent':
      return '你还没点同意，我不会把你的目标发出去。';
    case 'cors':
      return '浏览器把这家服务商挡在外面了。去设置里换一家能直连的，答案我记着。';
    case 'network':
    case 'timeout':
    case 'httpError':
      return '不是你的锅，是上游掉线。答案我都记着，点[重试]就行。';
    case 'badGoal':
      return '这个我不拆。换一个说法，或者换一个目标。';
    case 'quota':
      return '今天的份额用完了。[明天再来]，或者去设置里填你自己的 Key。答案我记着。';
    default:
      return '这次没拆明白。答案我都记着——[重试]，或者换个说法。';
  }
}
