import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bilicache_protocol/bilicache_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/utils/local_danmaku_file.dart';

void main() {
  test('zero-comment cache XML is valid while ordinary manual import keeps its validation', () {
    final bytes = Uint8List.fromList(utf8.encode('<?xml version="1.0"?><i><chatid>321</chatid></i>'));
    expect(parseBiliCacheDanmakuBytes(bytes)['count'], 0);
    expect(() => parseLocalDanmakuBytes(bytes), throwsFormatException);
  });
  test('BiliCache scan only includes the current complete revision', () async {
    final temp = await Directory.systemTemp.createTemp('nipaplay-bilicache-');
    addTearDown(() => temp.delete(recursive: true));
    final root = await temp.resolveSymbolicLinks();
    const rootId = '11111111-1111-4111-8111-111111111111';
    const revision = '22222222-2222-4222-8222-222222222222';
    const key = 'BV1xx411c7mD:321';
    final content = p.join(root, directoryForContent(key));
    final folder = p.join(content, revision);
    await Directory(folder).create(recursive: true);
    final video = utf8.encode('fixture'),
        xml = utf8.encode('<i><chatid>321</chatid></i>');
    Future<void> write(String file, Map<String, Object?> json) async {
      await File(file).writeAsString(jsonEncode(json));
    }

    await write(p.join(root, rootFile), {
      'format': 'bilicache-root',
      'version': 1,
      'rootId': rootId,
    });
    await write(p.join(content, contentFile), {
      'format': 'bilicache-content',
      'version': 1,
      'rootId': rootId,
      'contentKey': key,
    });
    await File(p.join(folder, 'sample.mp4')).writeAsBytes(video);
    await File(p.join(folder, 'sample.xml')).writeAsBytes(xml);
    final entry = <String, Object?>{
      'format': 'bilicache-entry',
      'version': 1,
      'rootId': rootId,
      'contentKey': key,
      'revision': revision,
      'state': 'complete',
      'bvid': 'BV1xx411c7mD',
      'cid': 321,
      'video': {
        'name': 'sample.mp4',
        'size': video.length,
        'sha256': sha256.convert(video).toString(),
      },
      'danmaku': {
        'name': 'sample.xml',
        'size': xml.length,
        'sha256': sha256.convert(xml).toString(),
      },
    };
    await write(p.join(content, 'entry.json'), entry);
    final path = p.join(folder, 'sample.mp4');
    expect(await shouldIncludeCacheVideo(path), true);
    expect(
      await shouldIncludeCacheVideo(p.join(content, rootId, 'sample.mp4')),
      false,
    );
    expect(
      (await probeCacheVideo(path))!.danmakuPath,
      p.join(folder, 'sample.xml'),
    );
    entry['state'] = 'removed';
    await write(p.join(content, 'entry.json'), entry);
    expect(await shouldIncludeCacheVideo(path), false);
    expect(await probeCacheVideo(p.join(root, 'ordinary.mp4')), null);
  });
}
