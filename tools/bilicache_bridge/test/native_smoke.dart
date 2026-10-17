// Executes compiled native framing and process argument transport in a private
// temp directory. Does not register a browser host or access player user data.
import 'dart:convert';
import 'dart:io';
import 'package:bilicache_bridge/host.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  const rootId = '11111111-1111-4111-8111-111111111111',
      revision = '22222222-2222-4222-8222-222222222222';
  const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      requestId = '44444444-4444-4444-8444-444444444444';
  final temp = await Directory.systemTemp.createTemp('bilicache-native-smoke-');
  try {
    final root = await temp.resolveSymbolicLinks(),
        suffix = Platform.isWindows ? '.exe' : '';
    final host = p.join(root, 'bilicache_bridge$suffix'),
        receiver = p.join(root, 'receiver$suffix');
    await File('build/bilicache_bridge$suffix').copy(host);
    final compile = await Process.run(Platform.resolvedExecutable,
        ['compile', 'exe', 'test/receiver.dart', '-o', receiver]);
    if (compile.exitCode != 0) throw StateError(compile.stderr.toString());
    Future<void> json(String name, Object value) async {
      await File(name).writeAsString(jsonEncode(value));
    }

    await json(p.join(root, 'config.json'), {
      'version': 1,
      'extensionId': id,
      'rootId': rootId,
      'rootPath': root,
      'playerPath': receiver,
      'paired': true
    });
    await json(p.join(root, '.bilicache-root.json'),
        {'format': 'bilicache-root', 'version': 1, 'rootId': rootId});
    final content = p.join(root, 'BV1xx411c7mD_321'),
        target = p.join(content, revision);
    await Directory(target).create(recursive: true);
    await json(p.join(content, '.bilicache-content.json'), {
      'format': 'bilicache-content',
      'version': 1,
      'rootId': rootId,
      'contentKey': 'BV1xx411c7mD:321'
    });
    final data = utf8.encode('fixture');
    for (final name in ['中文 空格.mp4', '中文 空格.xml'])
      await File(p.join(target, name)).writeAsBytes(data);
    await json(p.join(content, 'entry.json'), {
      'format': 'bilicache-entry',
      'version': 1,
      'rootId': rootId,
      'contentKey': 'BV1xx411c7mD:321',
      'bvid': 'BV1xx411c7mD',
      'cid': 321,
      'revision': revision,
      'state': 'complete',
      'video': {
        'name': '中文 空格.mp4',
        'size': data.length,
        'sha256': sha256.convert(data).toString()
      },
      'danmaku': {
        'name': '中文 空格.xml',
        'size': data.length,
        'sha256': sha256.convert(data).toString()
      }
    });
    final process = await Process.start(host, ['chrome-extension://$id/']);
    final responses = decodeFrames(process.stdout).toList(),
        errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.add(encodeFrame({
      'version': 1,
      'requestId': requestId,
      'operation': 'openCache',
      'rootId': rootId,
      'contentKey': 'BV1xx411c7mD:321'
    }));
    await process.stdin.close();
    final code = await process.exitCode, reply = await responses;
    if (code != 0 || reply.length != 1 || (reply.single as Map)['ok'] != true)
      throw StateError('native request failed: $reply ${await errors}');
    if (Platform.isWindows) {
      final captured = File(p.join(root, 'captured.json'));
      for (var i = 0; i < 100 && !await captured.exists(); i++)
        await Future<void>.delayed(const Duration(milliseconds: 20));
      final arguments = jsonDecode(await captured.readAsString());
      if (jsonEncode(arguments) != jsonEncode([p.join(target, '中文 空格.mp4')]))
        throw StateError('argument corruption');
    }
    final denied = await Process.run(
        host, ['chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/']);
    if (denied.exitCode == 0 || denied.stdout.toString().isNotEmpty)
      throw StateError('unregistered origin was accepted');
    stdout.writeln(
        'Native binary framing, origin gate and single-path process transport passed.');
  } finally {
    await temp.delete(recursive: true);
  }
}
