/// Web：证据不落盘（`vision_platform_web.dart` 的写文件是空实现），
/// 没有目录可删 —— 恒为「已清」。签名与 IO 版一致。
const String kEvidenceDirName = 'evidence';

Future<bool> wipeEvidence({Future<String> Function()? docsPath}) async => true;
