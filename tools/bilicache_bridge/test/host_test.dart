import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bilicache_bridge/host.dart';
import 'package:bilicache_protocol/bilicache_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const rootId = '11111111-1111-4111-8111-111111111111';
const revision = '22222222-2222-4222-8222-222222222222';
const nonce = '33333333-3333-4333-8333-333333333333';
const requestId = '44444444-4444-4444-8444-444444444444';
const key = 'BV1xx411c7mD:321';
Map<String, dynamic> request(String op,
        [Map<String, dynamic> fields = const {}]) =>
    {'version': 1, 'requestId': requestId, 'operation': op, ...fields};

void main() {
  test('shared protocol fixtures agree on content identity rules', () async {
    final fixture = jsonDecode(
        await File('../../protocol/bilicache-v1.json').readAsString());
    expect(fixture['version'], 1);
    for (final key in fixture['validContentKeys']) {
      expect(directoryForContent(key), (key as String).replaceFirst(':', '_'));
    }
    for (final key in fixture['invalidContentKeys']) {
      expect(() => directoryForContent(key), throwsA(isA<CacheFailure>()));
    }
  });
  late Directory temp;
  late String root, folder, target;
  late Map<String, dynamic> config, entry;
  late List<(String, List<String>)> launches;
  late NativeHost host;
  Future<void> write(String file, Object value) async {
    await File(file).writeAsString(jsonEncode(value));
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bilicache-host-test-');
    root = await temp.resolveSymbolicLinks();
    folder = p.join(root, directoryForContent(key));
    target = p.join(folder, revision);
    await Directory(target).create(recursive: true);
    await write(p.join(root, rootFile),
        {'format': 'bilicache-root', 'version': 1, 'rootId': rootId});
    await write(p.join(folder, contentFile), {
      'format': 'bilicache-content',
      'version': 1,
      'rootId': rootId,
      'contentKey': key
    });
    final video = utf8.encode('MP4 fixture'),
        xml = utf8.encode('<?xml version="1.0"?><i><chatid>321</chatid></i>');
    await File(p.join(target, '样本.mp4')).writeAsBytes(video);
    await File(p.join(target, '样本.xml')).writeAsBytes(xml);
    entry = {
      'format': 'bilicache-entry',
      'version': 1,
      'rootId': rootId,
      'contentKey': key,
      'bvid': 'BV1xx411c7mD',
      'cid': 321,
      'state': 'complete',
      'revision': revision,
      'video': {
        'name': '样本.mp4',
        'size': video.length,
        'sha256': sha256.convert(video).toString()
      },
      'danmaku': {
        'name': '样本.xml',
        'size': xml.length,
        'sha256': sha256.convert(xml).toString()
      }
    };
    await write(p.join(folder, 'entry.json'), entry);
    final player = p.join(root, 'NipaPlay.exe');
    await File(player).writeAsString('fixture, never executed');
    config = {
      'version': 1,
      'rootId': rootId,
      'rootPath': root,
      'playerPath': player,
      'paired': true
    };
    launches = [];
    host = NativeHost(config,
        platform: 'windows',
        save: (_) async {},
        now: () => 100000,
        launch: (exe, args) async {
          launches.add((exe, args));
        });
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });
  test('framing handles split headers, UTF-8 and consecutive requests',
      () async {
    final bytes = [
      ...encodeFrame(request('hello')),
      ...encodeFrame(request('hello'))
    ];
    expect(
        await decodeFrames(Stream.fromIterable(bytes.map((b) => [b]))).toList(),
        [request('hello'), request('hello')]);
  });
  test('oversized, malformed and truncated frames are rejected', () async {
    final huge = ByteData(4)..setUint32(0, 65537, Endian.little);
    for (final bytes in [
      huge.buffer.asUint8List(),
      [1, 0],
      [2, 0, 0, 0, 123],
      [1, 0, 0, 0, 0xff]
    ]) {
      await expectLater(
          decodeFrames(Stream.value(bytes)).toList(), throwsFormatException);
    }
  });
  test('arbitrary commands, paths, extra fields and versions never launch',
      () async {
    for (final value in [
      request('shell'),
      request('openCache', {
        'rootId': rootId,
        'contentKey': key,
        'args': ['--load-js=x']
      }),
      {...request('hello'), 'version': 2},
      {'operation': 'hello'}
    ]) {
      expect((await host.handle(value))['ok'], false);
    }
    expect(launches, isEmpty);
  });
  test('pairing consumes an expiring challenge from the configured root',
      () async {
    config['paired'] = false;
    final file = p.join(root, '.bilicache-pair-$nonce.json');
    await write(file,
        {'version': 1, 'rootId': rootId, 'nonce': nonce, 'expiresAt': 150000});
    expect(
        (await host.handle(
            request('pairRoot', {'rootId': rootId, 'nonce': nonce})))['ok'],
        true);
    expect(await File(file).exists(), false);
    expect(config['paired'], true);
    expect(
        (await host.handle(
            request('pairRoot', {'rootId': rootId, 'nonce': nonce})))['ok'],
        false);
  });
  test('copied marker, stale challenge and wrong root cannot pair', () async {
    config['paired'] = false;
    expect(
        (await host.handle(
            request('pairRoot', {'rootId': rootId, 'nonce': nonce})))['ok'],
        false);
    await write(p.join(root, '.bilicache-pair-$nonce.json'),
        {'version': 1, 'rootId': rootId, 'nonce': nonce, 'expiresAt': 99999});
    expect(
        (await host.handle(
            request('pairRoot', {'rootId': rootId, 'nonce': nonce})))['ok'],
        false);
    expect(
        (await host.handle(
            request('openCache', {'rootId': nonce, 'contentKey': key})))['ok'],
        false);
  });
  test('only paired complete current files reach a single player argument',
      () async {
    config['paired'] = false;
    expect(
        (await host.handle(
            request('openCache', {'rootId': rootId, 'contentKey': key})))['ok'],
        false);
    config['paired'] = true;
    final response = await host
        .handle(request('openCache', {'rootId': rootId, 'contentKey': key}));
    expect(response['result']['status'], 'launch_requested');
    expect(launches.single.$2, [p.join(target, '样本.mp4')]);
    expect(await shouldIncludeCacheVideo(p.join(target, '样本.mp4')), true);
    expect(
        await shouldIncludeCacheVideo(p.join(folder, nonce, '样本.mp4')), false);
  });
  test('edits, tombstones and traversal do not launch', () async {
    await File(p.join(target, '样本.mp4')).writeAsString('bad fixture');
    expect(
        (await host.handle(
            request('openCache', {'rootId': rootId, 'contentKey': key})))['ok'],
        false);
    expect(
        (await host.handle(request(
            'openCache', {'rootId': rootId, 'contentKey': '../../1'})))['ok'],
        false);
    entry['state'] = 'removed';
    await write(p.join(folder, 'entry.json'), entry);
    expect(
        (await host.handle(
            request('openCache', {'rootId': rootId, 'contentKey': key})))['ok'],
        false);
    expect(launches, isEmpty);
  });
  test('zero-comment XML resolves exactly; missing XML cannot fall back',
      () async {
    final result = (await probeCacheVideo(p.join(target, '样本.mp4')))!;
    expect(result.danmakuPath, p.join(target, '样本.xml'));
    await File(result.danmakuPath).delete();
    await expectLater(
        probeCacheVideo(result.videoPath), throwsA(isA<CacheFailure>()));
    expect(await shouldIncludeCacheVideo(result.videoPath), false);
  });
  test(
      'ordinary files remain ordinary; outside root and unsafe file names fail',
      () async {
    expect(await probeCacheVideo(p.join(root, 'ordinary.mp4')), null);
    await expectLater(assertNoLinks(root, p.join(root, '..', 'outside')),
        throwsA(isA<CacheFailure>()));
    entry['video']['name'] = '../escape.mp4';
    await write(p.join(folder, 'entry.json'), entry);
    expect(
        (await host.handle(
            request('openCache', {'rootId': rootId, 'contentKey': key})))['ok'],
        false);
  });
  test(
      'macOS uses fixed open executable and separate bundle and file arguments',
      () async {
    final app = p.join(root, 'Nipa Play.app');
    await Directory(app).create();
    config['playerPath'] = app;
    host = NativeHost(config, platform: 'macos', save: (_) async {},
        launch: (exe, args) async {
      launches.add((exe, args));
    });
    expect(
        (await host.handle(
            request('openCache', {'rootId': rootId, 'contentKey': key})))['ok'],
        true);
    expect(launches.single.$1, '/usr/bin/open');
    expect(launches.single.$2, ['-n', '-a', app, '--args', p.join(target, '样本.mp4')]);
  });
  test('repeated config saves replace atomically', () async {
    final file = p.join(root, 'config.json');
    await saveConfig(file, config);
    await saveConfig(file, {...config, 'paired': false});
    expect((await readObject(file))['paired'], false);
  });
}
