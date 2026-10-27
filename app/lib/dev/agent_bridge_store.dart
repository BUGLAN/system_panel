/// 平台桥：截图落盘。IO 写真机目录，Web 直接返回 null。
export 'agent_bridge_store_io.dart'
    if (dart.library.html) 'agent_bridge_store_web.dart';
