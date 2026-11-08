import 'dart:io';

import 'templates.dart';

/// Result of running `dart run firebase_kit:scaffold`.
class ScaffoldResult {
  const ScaffoldResult({
    required this.exitCode,
    required this.writtenFiles,
    required this.driftedFiles,
    required this.createdEnvFile,
  });

  final int exitCode;
  final List<String> writtenFiles;
  final List<String> driftedFiles;
  final bool createdEnvFile;
}

/// Executes the `firebase_kit:scaffold` command against [targetDir].
///
/// Must not import Flutter so it can run directly under `dart run`.
Future<ScaffoldResult> runScaffold({
  required List<String> args,
  Directory? targetDir,
  StringSink? out,
  StringSink? err,
}) async {
  final root = targetDir ?? Directory.current;
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  final checkOnly = args.contains('--check');
  if (args.contains('--help') || args.contains('-h')) {
    stdoutSink.writeln(
      'Usage: dart run firebase_kit:scaffold [--check]\n'
      '\n'
      'Writes managed Firebase dev/test scripts into the current Flutter app,\n'
      'and creates scripts/firebase_kit.env if missing.\n'
      '\n'
      'Options:\n'
      '  --check    Verify that all managed files match firebase_kit '
      'v$firebaseKitScaffoldVersion without modifying any files.',
    );
    return const ScaffoldResult(
      exitCode: 0,
      writtenFiles: [],
      driftedFiles: [],
      createdEnvFile: false,
    );
  }

  if (checkOnly) {
    final drifted = <String>[];
    for (final item in managedScaffoldFiles) {
      final file = File('${root.path}/${item.relativePath}');
      if (!file.existsSync()) {
        drifted.add('${item.relativePath} (missing)');
        continue;
      }
      final existing = await file.readAsString();
      if (existing != item.content) {
        drifted.add('${item.relativePath} (modified)');
      }
    }

    if (drifted.isNotEmpty) {
      stderrSink.writeln(
        'firebase_kit:scaffold --check failed. The following managed files '
        'differ from firebase_kit v$firebaseKitScaffoldVersion:',
      );
      for (final item in drifted) {
        stderrSink.writeln('  - $item');
      }
      stderrSink.writeln(
        'Run `dart run firebase_kit:scaffold` to update managed files.',
      );
      return ScaffoldResult(
        exitCode: 1,
        writtenFiles: const [],
        driftedFiles: drifted,
        createdEnvFile: false,
      );
    }

    stdoutSink.writeln(
      'All ${managedScaffoldFiles.length} firebase_kit managed files are up to '
      'date (v$firebaseKitScaffoldVersion).',
    );
    return const ScaffoldResult(
      exitCode: 0,
      writtenFiles: [],
      driftedFiles: [],
      createdEnvFile: false,
    );
  }

  final written = <String>[];
  for (final item in managedScaffoldFiles) {
    final file = File('${root.path}/${item.relativePath}');
    await file.parent.create(recursive: true);
    await file.writeAsString(item.content);
    if (item.executable && !Platform.isWindows) {
      await Process.run('chmod', ['+x', file.path]);
    }
    written.add(item.relativePath);
    stdoutSink.writeln('Wrote ${item.relativePath}');
  }

  final envFile = File('${root.path}/$firebaseKitEnvRelativePath');
  var createdEnv = false;
  if (!envFile.existsSync()) {
    await envFile.parent.create(recursive: true);
    await envFile.writeAsString(defaultFirebaseKitEnv);
    createdEnv = true;
    stdoutSink.writeln('Created $firebaseKitEnvRelativePath');
  } else {
    stdoutSink.writeln('Kept existing $firebaseKitEnvRelativePath');
  }

  return ScaffoldResult(
    exitCode: 0,
    writtenFiles: written,
    driftedFiles: const [],
    createdEnvFile: createdEnv,
  );
}
