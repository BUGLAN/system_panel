/**
 * core 只用到这几个宿主全局：浏览器与 Node 都有，但不在 ES 标准库里。
 * 故意不引 DOM / @types/node，防止纯逻辑层误用平台 API。
 */
declare function structuredClone<T>(value: T): T;
/** Base64（导出包里的照片）：同样是浏览器与 Node 共有的全局 */
declare function btoa(data: string): string;
declare function atob(data: string): string;
