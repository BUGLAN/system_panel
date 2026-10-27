/// 证据模型 + 视觉校验公共 API。
///
/// 平台相关（落盘目录 / 写文件）走 vision_platform.dart 的条件导入，
/// 这样同一个 VisionService 在 IO 与 Web 上都能编译。
export 'vision_core.dart';
