import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:bilicache_protocol/bilicache_protocol.dart';
import 'package:bilicache_bridge/host.dart';

Future<void> main(List<String> args) async {
  try {
    final configPath =
        p.join(p.dirname(Platform.resolvedExecutable), 'config.json');
    final config = await readObject(configPath);
    if (config['version'] != 1 ||
        config['extensionId'] is! String ||
        !RegExp(r'^[a-p]{32}$').hasMatch(config['extensionId']) ||
        args.isEmpty ||
        args.first != 'chrome-extension://${config['extensionId']}/') {
      stderr.writeln('BiliCache: caller is not registered.');
      exitCode = 1;
      return;
    }
    final host = NativeHost(config,
        platform: Platform.operatingSystem,
        save: (value) => saveConfig(configPath, value));
    await for (final request in decodeFrames(stdin)) {
      stdout.add(encodeFrame(await host.handle(request)));
      await stdout.flush();
    }
  } catch (_) {
    stderr.writeln('BiliCache: invalid configuration or protocol frame.');
    exitCode = 1;
  }
}
