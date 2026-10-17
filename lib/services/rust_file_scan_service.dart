import 'package:flutter/foundation.dart';
import 'package:bilicache_protocol/bilicache_protocol.dart' as bilicache;
import 'package:path/path.dart' as p;
import 'package:nipaplay/src/rust/api/file_scan.dart' as rust;
import 'package:nipaplay/src/rust/rust_init.dart';

class RustFileScanResult {
  const RustFileScanResult({
    required this.currentCount,
    required this.cachedCount,
    required this.currentFiles,
    required this.newFiles,
    required this.modifiedFiles,
    required this.deletedFiles,
    required this.currentHashes,
  });

  final int currentCount;
  final int cachedCount;
  final List<String> currentFiles;
  final List<String> newFiles;
  final List<String> modifiedFiles;
  final List<String> deletedFiles;
  final Map<String, String> currentHashes;
}

class RustFileScanService {
  const RustFileScanService._();

  static Future<RustFileScanResult> calculateDiff({
    required String folderPath,
    required Map<String, String> cachedHashes,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Rust file scan is not available on Web.');
    }
    await ensureRustInitialized();
    final diff = await rust.diffVideoFiles(
      folderPath: folderPath,
      cachedHashes: cachedHashes.entries
          .map(
            (entry) => rust.RustFileHashEntry(
              relativePath: entry.key,
              hash: entry.value,
            ),
          )
          .toList(growable: false),
    );

    final allowed = <String>{};
    for (final file in diff.currentFiles) {
      if (await bilicache.shouldIncludeCacheVideo(p.join(folderPath, file)))
        allowed.add(file);
    }
    final deleted = {
      ...diff.deletedFiles,
      ...cachedHashes.keys.where((file) => !allowed.contains(file)),
    }.toList()..sort();
    return RustFileScanResult(
      currentCount: allowed.length,
      cachedCount: diff.cachedCount,
      currentFiles: diff.currentFiles.where(allowed.contains).toList(),
      newFiles: diff.newFiles.where(allowed.contains).toList(),
      modifiedFiles: diff.modifiedFiles.where(allowed.contains).toList(),
      deletedFiles: deleted,
      currentHashes: {
        for (final entry in diff.currentHashes)
          if (allowed.contains(entry.relativePath))
            entry.relativePath: entry.hash,
      },
    );
  }
}
