import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_panel/state/evidence_store.dart';

/// G3.2 证据照片：原来只写不删，「重置 = 全部清空」对照片不成立。
/// 宿主定案：只在重置存档时清整个 `evidence/`（结算 / 认输后不删）。
void main() {
  late Directory docs;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('g_evidence_');
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  /// 照 vision_core 的落盘布局造几张：`evidence/q<serial>/<name>.jpg`
  Future<File> photo(int serial, String name) async {
    final File f = File(
      '${docs.path}${Platform.pathSeparator}$kEvidenceDirName'
      '${Platform.pathSeparator}q$serial${Platform.pathSeparator}$name.jpg',
    );
    await f.create(recursive: true);
    await f.writeAsBytes(<int>[0xFF, 0xD8, 0xFF]);
    return f;
  }

  test('删掉整个 evidence/，文档目录里别的东西不动', () async {
    final File a = await photo(41, 'a');
    final File b = await photo(42, 'b');
    final File keep = File('${docs.path}${Platform.pathSeparator}other.txt');
    await keep.writeAsString('别删我');

    expect(await wipeEvidence(docsPath: () async => docs.path), isTrue);
    expect(await a.exists(), isFalse);
    expect(await b.exists(), isFalse);
    expect(
      await Directory('${docs.path}${Platform.pathSeparator}$kEvidenceDirName')
          .exists(),
      isFalse,
    );
    expect(await keep.readAsString(), '别删我');
  });

  test('本来就没有 evidence/ → 当作已清，不抛', () async {
    expect(await wipeEvidence(docsPath: () async => docs.path), isTrue);
  });

  test('取文档目录失败 / 为空 → 永不抛', () async {
    expect(
      await wipeEvidence(docsPath: () async => throw StateError('没有目录')),
      isFalse,
    );
    expect(await wipeEvidence(docsPath: () async => ''), isTrue);
  });
}
