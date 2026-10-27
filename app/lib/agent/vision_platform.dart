/// 平台桥：IO 走 path_provider 落盘；Web 只留内存字节。
export 'vision_platform_io.dart'
    if (dart.library.html) 'vision_platform_web.dart';
