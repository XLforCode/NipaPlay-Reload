// A native smoke-test receiver, never included in release packages.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  await File(
          '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}captured.json')
      .writeAsString(jsonEncode(args));
}
