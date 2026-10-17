import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:bilicache_protocol/bilicache_protocol.dart';
import 'package:bilicache_bridge/host.dart';

Future<void> main(List<String> args) async {
  try {
    if (!Platform.isWindows && !Platform.isMacOS)
      throw StateError('Only Windows and macOS are supported.');
    final options = <String, String>{};
    for (var i = 1; i < args.length; i += 2) {
      if (i + 1 >= args.length ||
          !args[i].startsWith('--') ||
          options.containsKey(args[i])) throw ArgumentError('Invalid options.');
      options[args[i]] = args[i + 1];
    }
    final base = Platform.isWindows
        ? p.join(Platform.environment['LOCALAPPDATA']!, 'BiliCacheBridge')
        : p.join(Platform.environment['HOME']!, 'Library',
            'Application Support', 'BiliCacheBridge');
    final manifest = p.join(base, '$hostName.json');
    final configPath = p.join(base, 'config.json');
    final registryKey =
        r'HKCU\Software\Google\Chrome\NativeMessagingHosts\' + hostName;
    final macRegistration = Platform.isMacOS
        ? p.join(
            Platform.environment['HOME']!,
            'Library',
            'Application Support',
            'Google',
            'Chrome',
            'NativeMessagingHosts',
            '$hostName.json')
        : '';
    final operation = args.isEmpty ? 'help' : args.first;
    if (operation == 'install') {
      if (options.keys.any((key) =>
          !['--extension-id', '--cache-root', '--player'].contains(key)))
        throw ArgumentError('Unknown option.');
      final id = options['--extension-id'] ?? '';
      if ((options['--cache-root'] ?? '').isEmpty ||
          (options['--player'] ?? '').isEmpty) {
        throw ArgumentError('Cache root and player path are required.');
      }
      if (!RegExp(r'^[a-p]{32}$').hasMatch(id))
        throw ArgumentError(
            'A real 32-character Chrome extension ID is required.');
      final root =
          await Directory(options['--cache-root'] ?? '').resolveSymbolicLinks();
      final marker = await readObject(p.join(root, rootFile));
      if (marker['format'] != 'bilicache-root' ||
          marker['version'] != 1 ||
          !validUUID(marker['rootId']))
        throw StateError('Choose a root created by the extension first.');
      final player = p.normalize(p.absolute(options['--player'] ?? ''));
      if (Platform.isWindows
          ? !player.toLowerCase().endsWith('.exe') ||
              !await File(player).exists()
          : !player.endsWith('.app') || !await Directory(player).exists())
        throw ArgumentError('Player path does not exist.');
      final filename =
          Platform.isWindows ? 'bilicache_bridge.exe' : 'bilicache_bridge';
      final source =
          File(p.join(p.dirname(Platform.resolvedExecutable), filename));
      if (!await source.exists())
        throw StateError(
            'Keep setup and bridge in the same release directory.');
      await Directory(base).create(recursive: true);
      await source.copy(p.join(base, filename));
      final config = <String, dynamic>{
        'version': 1,
        'extensionId': id,
        'rootPath': root,
        'rootId': marker['rootId'],
        'playerPath': player,
        'paired': false
      };
      await saveConfig(configPath, config);
      final registration = <String, dynamic>{
        'name': hostName,
        'description': 'BiliCache player bridge',
        'path': p.join(base, filename),
        'type': 'stdio',
        'allowed_origins': ['chrome-extension://$id/']
      };
      await File(manifest).writeAsString(jsonEncode(registration), flush: true);
      if (Platform.isWindows) {
        final result = await Process.run('reg.exe',
            ['ADD', registryKey, '/ve', '/t', 'REG_SZ', '/d', manifest, '/f']);
        if (result.exitCode != 0)
          throw StateError('Could not register current-user native host.');
      } else {
        await File(macRegistration).parent.create(recursive: true);
        await File(macRegistration)
            .writeAsString(jsonEncode(registration), flush: true);
      }
      stdout.writeln(
          'Installed. Click Pair player in the extension. macOS: add the same root to NipaPlay once to save sandbox permission.');
    } else if (operation == 'check') {
      final config = await readObject(configPath),
          registration =
              await readObject(Platform.isWindows ? manifest : macRegistration);
      if (registration['name'] != hostName ||
          !await File(registration['path']).exists())
        throw StateError('Host registration is invalid.');
      final marker = await readObject(p.join(config['rootPath'], rootFile));
      if (marker['rootId'] != config['rootId'])
        throw StateError('Root identity changed. Reinstall and pair again.');
      if (Platform.isWindows) {
        final result =
            await Process.run('reg.exe', ['QUERY', registryKey, '/ve']);
        if (result.exitCode != 0 ||
            !result.stdout.toString().contains(manifest))
          throw StateError('Current-user registry entry is missing.');
      }
      stdout.writeln('Registration OK; paired=${config['paired'] == true}.');
    } else if (operation == 'uninstall') {
      // Delete only exact files installed by this tool. Never recurse into the
      // configured media root, even if a local config has been edited.
      if (Platform.isWindows) {
        final result =
            await Process.run('reg.exe', ['QUERY', registryKey, '/ve']);
        if (result.exitCode == 0 &&
            result.stdout.toString().contains(manifest)) {
          await Process.run('reg.exe', ['DELETE', registryKey, '/f']);
        }
      } else if (await File(macRegistration).exists()) {
        final registration = await readObject(macRegistration);
        if (registration['name'] == hostName &&
            p.dirname(registration['path']) == base)
          await File(macRegistration).delete();
      }
      for (final name in [
        'config.json',
        '$hostName.json',
        Platform.isWindows ? 'bilicache_bridge.exe' : 'bilicache_bridge'
      ]) {
        final file = File(p.join(base, name));
        if (await file.exists()) await file.delete();
      }
      stdout.writeln(
          'Bridge unregistered. Cached media and player settings were preserved.');
    } else {
      stdout.writeln(
          'BiliCache setup\ninstall --extension-id ID --cache-root PATH --player PATH\ncheck\nuninstall');
    }
  } catch (error) {
    stderr.writeln('BiliCache setup: $error');
    exitCode = 1;
  }
}
