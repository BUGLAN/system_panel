import 'dart:io';
import 'dart:typed_data';

Future<String?> saveAgentScreenshot(Uint8List bytes, String name) async {
  final String dir = Platform.isAndroid ? '/sdcard/agent' : '/tmp/agent';
  final Directory d = Directory(dir);
  if (!await d.exists()) await d.create(recursive: true);
  final int ts = DateTime.now().millisecondsSinceEpoch;
  final String path = dir + '/' + name + '_' + ts.toString() + '.png';
  await File(path).writeAsBytes(bytes);
  return path;
}
