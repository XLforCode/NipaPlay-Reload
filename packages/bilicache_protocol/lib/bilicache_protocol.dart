library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const rootFile = '.bilicache-root.json';
const contentFile = '.bilicache-content.json';
const protocolVersion = 1;
final _uuid = RegExp(r'^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$');
final _key = RegExp(r'^(BV[\da-zA-Z]{10}):([1-9]\d*)$');

class CacheFailure implements Exception {
  final String code;
  final String message;
  const CacheFailure(this.code, this.message);
  @override
  String toString() => '$code: $message';
}

String directoryForContent(String key) {
  final match = _key.firstMatch(key);
  if (match == null ||
      int.tryParse(match[2]!) == null ||
      int.parse(match[2]!) > 9007199254740991) {
    throw const CacheFailure('INVALID_CONTENT', 'Invalid content identity.');
  }
  return '${match[1]}_${match[2]}';
}

bool validUUID(Object? value) => value is String && _uuid.hasMatch(value);
bool safeComponent(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= 240 &&
    !RegExp(r'[\\/:*?"<>|\x00-\x1f\x7f]').hasMatch(value) &&
    !RegExp(r'[.\s]$').hasMatch(value) &&
    value != '.' &&
    value != '..';

Future<Map<String, dynamic>> readObject(String filePath) async {
  final file = File(filePath);
  if (await file.length() > 1024 * 1024) {
    throw const CacheFailure('INVALID_MANIFEST', 'Metadata exceeds 1 MiB.');
  }
  final value = jsonDecode(await file.readAsString());
  if (value is! Map<String, dynamic>) {
    throw const CacheFailure('INVALID_MANIFEST', 'Metadata must be an object.');
  }
  return value;
}

Future<void> assertNoLinks(String canonicalRoot, String candidate) async {
  final root = p.normalize(p.absolute(canonicalRoot));
  final target = p.normalize(p.absolute(candidate));
  if (!p.equals(root, target) && !p.isWithin(root, target)) {
    throw const CacheFailure(
      'PATH_ESCAPE',
      'Path is outside the selected root.',
    );
  }
  var next = root;
  for (final component in <String>[
    '',
    ...p.split(p.relative(target, from: root)).where((v) => v != '.'),
  ]) {
    if (component.isNotEmpty) next = p.join(next, component);
    final type = await FileSystemEntity.type(next, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const CacheFailure(
        'MISSING',
        'A cache file or directory is missing.',
      );
    }
    if (type == FileSystemEntityType.link) {
      throw const CacheFailure(
        'PATH_ESCAPE',
        'Links are not accepted in cache paths.',
      );
    }
    final resolved = type == FileSystemEntityType.directory
        ? await Directory(next).resolveSymbolicLinks()
        : await File(next).resolveSymbolicLinks();
    if (!p.equals(p.normalize(resolved), p.normalize(next))) {
      throw const CacheFailure(
        'PATH_ESCAPE',
        'Reparse points are not accepted.',
      );
    }
  }
}

class CacheFileDescriptor {
  final String name;
  final int size;
  final String hash;
  CacheFileDescriptor._(this.name, this.size, this.hash);
  factory CacheFileDescriptor.parse(Object? value, String extension) {
    if (value is! Map<String, dynamic> ||
        !safeComponent(value['name']) ||
        !(value['name'] as String).endsWith(extension) ||
        value['size'] is! int ||
        value['size'] <= 0 ||
        value['size'] > 9007199254740991 ||
        value['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'])) {
      throw const CacheFailure('INVALID_MANIFEST', 'Invalid file descriptor.');
    }
    return CacheFileDescriptor._(value['name'], value['size'], value['sha256']);
  }
  Future<void> verify(String path, {bool hashes = true}) async {
    final file = File(path);
    if (await file.length() != size) {
      throw const CacheFailure(
        'FILE_CHANGED',
        'A cache file has changed size.',
      );
    }
    if (hashes &&
        (await sha256.bind(file.openRead()).first).toString() != hash) {
      throw const CacheFailure(
        'FILE_CHANGED',
        'A cache file has been modified.',
      );
    }
  }
}

class CacheEntry {
  final String rootId, contentKey, revision;
  final CacheFileDescriptor video, danmaku;
  final Map<String, dynamic> json;
  CacheEntry._(
    this.rootId,
    this.contentKey,
    this.revision,
    this.video,
    this.danmaku,
    this.json,
  );
  factory CacheEntry.parse(
    Map<String, dynamic> value, {
    required String rootId,
    required String contentKey,
  }) {
    directoryForContent(contentKey);
    if (value['format'] != 'bilicache-entry' ||
        value['version'] != 1 ||
        value['state'] != 'complete' ||
        !validUUID(rootId) ||
        value['rootId'] != rootId ||
        value['contentKey'] != contentKey ||
        !validUUID(value['revision']) ||
        '${value['bvid']}:${value['cid']}' != contentKey) {
      throw const CacheFailure(
        'INCOMPLETE',
        'No compatible complete cache revision.',
      );
    }
    final video = CacheFileDescriptor.parse(value['video'], '.mp4');
    final xml = CacheFileDescriptor.parse(value['danmaku'], '.xml');
    if (p.basenameWithoutExtension(video.name) !=
        p.basenameWithoutExtension(xml.name)) {
      throw const CacheFailure(
        'INVALID_MANIFEST',
        'MP4 and XML names must match.',
      );
    }
    return CacheEntry._(
      rootId,
      contentKey,
      value['revision'],
      video,
      xml,
      value,
    );
  }
}

class ResolvedCache {
  final CacheEntry entry;
  final String rootPath, videoPath, danmakuPath;
  ResolvedCache(this.entry, this.rootPath, this.videoPath, this.danmakuPath);
}

Future<ResolvedCache> resolveCache(
  String rootPath,
  String rootId,
  String contentKey, {
  bool hashes = true,
}) async {
  final root = p.normalize(p.absolute(rootPath));
  final folder = p.join(root, directoryForContent(contentKey));
  for (final path in [
    root,
    p.join(root, rootFile),
    folder,
    p.join(folder, contentFile),
    p.join(folder, 'entry.json'),
  ]) {
    await assertNoLinks(root, path);
  }
  final rootMarker = await readObject(p.join(root, rootFile));
  final contentMarker = await readObject(p.join(folder, contentFile));
  if (rootMarker['format'] != 'bilicache-root' ||
      rootMarker['version'] != 1 ||
      rootMarker['rootId'] != rootId ||
      contentMarker['format'] != 'bilicache-content' ||
      contentMarker['version'] != 1 ||
      contentMarker['rootId'] != rootId ||
      contentMarker['contentKey'] != contentKey) {
    throw const CacheFailure(
      'WRONG_ROOT',
      'Cache root or content marker does not match.',
    );
  }
  final entry = CacheEntry.parse(
    await readObject(p.join(folder, 'entry.json')),
    rootId: rootId,
    contentKey: contentKey,
  );
  final video = p.join(folder, entry.revision, entry.video.name);
  final xml = p.join(folder, entry.revision, entry.danmaku.name);
  for (final path in [video, xml]) {
    await assertNoLinks(root, path);
  }
  await entry.video.verify(video, hashes: hashes);
  await entry.danmaku.verify(xml, hashes: hashes);
  return ResolvedCache(entry, root, video, xml);
}

// null means ordinary media. A marked but invalid BiliCache path throws, so it
// never falls through to fuzzy XML matching or network danmaku.
Future<ResolvedCache?> probeCacheVideo(
  String videoPath, {
  bool hashes = true,
}) async {
  if (!p.isAbsolute(videoPath)) return null;
  final content = p.dirname(p.dirname(videoPath));
  final root = p.dirname(content);
  final rootMarker = File(p.join(root, rootFile));
  final contentMarker = File(p.join(content, contentFile));
  if (!await rootMarker.exists() && !await contentMarker.exists()) return null;
  final marker = await readObject(contentMarker.path);
  if (marker['contentKey'] is! String || marker['rootId'] is! String) {
    throw const CacheFailure('INVALID_MANIFEST', 'Invalid cache identity.');
  }
  final resolved = await resolveCache(
    root,
    marker['rootId'],
    marker['contentKey'],
    hashes: hashes,
  );
  if (!p.equals(p.normalize(resolved.videoPath), p.normalize(videoPath))) {
    throw const CacheFailure(
      'INACTIVE_REVISION',
      'Only the current complete cache revision can be opened.',
    );
  }
  return resolved;
}

Future<bool> shouldIncludeCacheVideo(String videoPath) async {
  try {
    await probeCacheVideo(videoPath, hashes: false);
    return true;
  } catch (_) {
    return false;
  }
}
