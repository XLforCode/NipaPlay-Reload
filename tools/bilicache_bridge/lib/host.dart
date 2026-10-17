import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:bilicache_protocol/bilicache_protocol.dart';
import 'package:path/path.dart' as p;

const hostName = 'com.xlforcode.bilicache';
typedef Launcher = Future<void> Function(
    String executable, List<String> arguments);
typedef ConfigSaver = Future<void> Function(Map<String, dynamic> value);

Future<void> launchProcess(String executable, List<String> arguments) async {
  final process = await Process.start(executable, arguments,
      mode: ProcessStartMode.detached);
  if (process.pid <= 0)
    throw const CacheFailure(
        'LAUNCH_FAILED', 'Could not start the configured application.');
}

class NativeHost {
  final Map<String, dynamic> config;
  final String platform;
  final Launcher launch;
  final ConfigSaver save;
  final int Function() now;
  NativeHost(this.config,
      {required this.platform,
      required this.save,
      Launcher? launch,
      int Function()? now})
      : launch = launch ?? launchProcess,
        now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  Future<Map<String, dynamic>> handle(Object? value) async {
    Object? requestId = value is Map ? value['requestId'] : null;
    final base = <String, dynamic>{'version': 1, 'requestId': requestId};
    try {
      if (value is! Map<String, dynamic> ||
          !validUUID(requestId) ||
          value['version'] != 1 ||
          value['operation'] is! String) {
        throw const CacheFailure(
            'INVALID_REQUEST', 'Invalid protocol version or request.');
      }
      final operation = value['operation'];
      final fields = switch (operation) {
        'hello' => <String>[],
        'pairRoot' => ['rootId', 'nonce'],
        'openCache' || 'revealCache' => ['rootId', 'contentKey'],
        _ => throw const CacheFailure(
            'UNSUPPORTED_OPERATION', 'Unsupported operation.')
      };
      final allowed = {'version', 'requestId', 'operation', ...fields};
      if (value.keys.any((key) => !allowed.contains(key))) {
        throw const CacheFailure(
            'INVALID_REQUEST', 'Unexpected request fields.');
      }
      if (operation == 'hello') {
        return {
          ...base,
          'ok': true,
          'result': {
            'platform': platform,
            'capabilities': ['pairRoot', 'openCache', 'revealCache']
          }
        };
      }
      if (!validUUID(value['rootId']) ||
          value['rootId'] != config['rootId'] ||
          config['rootPath'] is! String) {
        throw const CacheFailure('WRONG_ROOT',
            'Select the same cache root during bridge installation.');
      }
      final root = config['rootPath'] as String;
      await assertNoLinks(root, p.join(root, rootFile));
      final marker = await readObject(p.join(root, rootFile));
      if (marker['rootId'] != value['rootId'] ||
          marker['format'] != 'bilicache-root' ||
          marker['version'] != 1) {
        throw const CacheFailure(
            'WRONG_ROOT', 'Cache root identity has changed.');
      }
      if (operation == 'pairRoot') {
        final nonce = value['nonce'];
        if (!validUUID(nonce) || config['lastNonce'] == nonce) {
          throw const CacheFailure(
              'INVALID_CHALLENGE', 'Invalid or already consumed challenge.');
        }
        final path = p.join(root, '.bilicache-pair-$nonce.json');
        await assertNoLinks(root, path);
        final challenge = await readObject(path);
        final expiry = challenge['expiresAt'];
        if (challenge['version'] != 1 ||
            challenge['rootId'] != value['rootId'] ||
            challenge['nonce'] != nonce ||
            expiry is! int ||
            expiry < now() ||
            expiry > now() + 120000) {
          throw const CacheFailure('INVALID_CHALLENGE',
              'Pairing challenge expired or does not match.');
        }
        final next = {...config, 'paired': true, 'lastNonce': nonce};
        await save(next);
        config.addAll(next);
        await File(path).delete();
        return {
          ...base,
          'ok': true,
          'result': {'paired': true}
        };
      }
      if (config['paired'] != true) {
        throw const CacheFailure(
            'UNPAIRED', 'Click Pair player in the extension first.');
      }
      if (value['contentKey'] is! String)
        throw const CacheFailure(
            'INVALID_CONTENT', 'Missing content identity.');
      final cache =
          await resolveCache(root, value['rootId'], value['contentKey']);
      // Detect a pointer switch that occurred while hashing the files.
      final latest = await readObject(p.join(
          root, directoryForContent(cache.entry.contentKey), 'entry.json'));
      if (jsonEncode(latest) != jsonEncode(cache.entry.json))
        throw const CacheFailure(
            'REVISION_CHANGED', 'The current cache changed; retry.');
      if (operation == 'openCache') {
        final player = config['playerPath'];
        if (player is! String || !p.isAbsolute(player))
          throw const CacheFailure(
              'PLAYER_MISSING', 'Configure the player path again.');
        if (platform == 'windows') {
          if (!player.toLowerCase().endsWith('.exe') ||
              !await File(player).exists()) {
            throw const CacheFailure(
                'PLAYER_MISSING', 'Configured player executable is missing.');
          }
          await launch(player, [cache.videoPath]);
        } else if (platform == 'macos') {
          if (!player.endsWith('.app') || !await Directory(player).exists()) {
            throw const CacheFailure(
                'PLAYER_MISSING', 'Configured application bundle is missing.');
          }
          // A forced launch targets this bundle even if another NipaPlay build
          // shares its bundle ID. CLI args then reach the fork's single-instance
          // handoff, so cold and hot opens use the same verified local path.
          await launch('/usr/bin/open', ['-n', '-a', player, '--args', cache.videoPath]);
        } else {
          throw const CacheFailure(
              'UNSUPPORTED_PLATFORM', 'Only Windows and macOS are supported.');
        }
        return {
          ...base,
          'ok': true,
          'result': {'status': 'launch_requested'}
        };
      }
      if (platform == 'windows') {
        final explorer = p.join(
            Platform.environment['WINDIR'] ?? r'C:\Windows', 'explorer.exe');
        await launch(explorer, ['/select,', cache.videoPath]);
      } else if (platform == 'macos') {
        await launch('/usr/bin/open', ['-R', cache.videoPath]);
      } else {
        throw const CacheFailure(
            'UNSUPPORTED_PLATFORM', 'Only Windows and macOS are supported.');
      }
      return {
        ...base,
        'ok': true,
        'result': {'status': 'reveal_requested'}
      };
    } on CacheFailure catch (error) {
      return {
        ...base,
        'ok': false,
        'error': {'code': error.code, 'message': error.message}
      };
    } on FileSystemException {
      return {
        ...base,
        'ok': false,
        'error': {
          'code': 'FILE_ACCESS',
          'message': 'A cache file is missing, in use, or needs permission.'
        }
      };
    } on FormatException {
      return {
        ...base,
        'ok': false,
        'error': {
          'code': 'INVALID_MANIFEST',
          'message': 'Invalid cache metadata.'
        }
      };
    } catch (_) {
      return {
        ...base,
        'ok': false,
        'error': {'code': 'HOST_ERROR', 'message': 'Bridge operation failed.'}
      };
    }
  }
}

// Incremental framing handles split headers/bodies and multiple requests. Never
// decode unbounded input, and keep stdout reserved for protocol frames.
Stream<Object?> decodeFrames(Stream<List<int>> input) async* {
  var buffer = <int>[];
  int? expected;
  await for (final chunk in input) {
    var offset = 0;
    while (offset < chunk.length) {
      final needed = (expected ?? 4) - buffer.length;
      final length = min(needed, chunk.length - offset);
      buffer.addAll(chunk.sublist(offset, offset + length));
      offset += length;
      if (expected == null && buffer.length == 4) {
        expected = ByteData.sublistView(Uint8List.fromList(buffer))
            .getUint32(0, Endian.little);
        buffer = [];
        if (expected <= 0 || expected > 65536)
          throw const FormatException('Invalid frame size.');
      } else if (expected != null && buffer.length == expected) {
        yield jsonDecode(utf8.decode(buffer));
        buffer = [];
        expected = null;
      }
    }
  }
  if (buffer.isNotEmpty || expected != null)
    throw const FormatException('Truncated frame.');
}

Uint8List encodeFrame(Map<String, dynamic> value) {
  final body = utf8.encode(jsonEncode(value));
  final header = ByteData(4)..setUint32(0, body.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...body]);
}

Future<void> saveConfig(String path, Map<String, dynamic> config) async {
  final random = Random.secure().nextInt(0x7fffffff);
  final temporary = File('$path.$random.tmp');
  try {
    await temporary.writeAsString(jsonEncode(config), flush: true);
    await temporary.rename(path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
