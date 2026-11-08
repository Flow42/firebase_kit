import 'dart:io';

import 'package:firebase_kit/src/scaffold/scaffold_runner.dart';
import 'package:firebase_kit/src/scaffold/templates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('firebase_kit_scaffold_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('writes all managed files with versioned DO NOT EDIT header', () async {
    final out = StringBuffer();
    final err = StringBuffer();

    final result = await runScaffold(
      args: const [],
      targetDir: tempDir,
      out: out,
      err: err,
    );

    expect(result.exitCode, 0);
    expect(result.createdEnvFile, isTrue);
    expect(err.toString(), isEmpty);

    const expectedManaged = [
      'scripts/run_dev.sh',
      'scripts/test_integration.sh',
      'scripts/test_security_rules.sh',
      'test_driver/integration_test.dart',
      'test/security_rules/rules_test_env.mjs',
    ];
    expect(result.writtenFiles, expectedManaged);

    for (final relativePath in expectedManaged) {
      final file = File('${tempDir.path}/$relativePath');
      expect(await file.exists(), isTrue, reason: '$relativePath should exist');
      final content = await file.readAsString();
      expect(
        content,
        contains(
          'Managed by firebase_kit v$firebaseKitScaffoldVersion — DO NOT EDIT BY HAND.',
        ),
        reason: '$relativePath should contain versioned header',
      );
    }

    final envFile = File('${tempDir.path}/scripts/firebase_kit.env');
    expect(await envFile.exists(), isTrue);
  });

  test('preserves existing scripts/firebase_kit.env on re-run', () async {
    await runScaffold(
      args: const [],
      targetDir: tempDir,
      out: StringBuffer(),
      err: StringBuffer(),
    );

    final envFile = File('${tempDir.path}/scripts/firebase_kit.env');
    const customEnv = 'FIREBASE_PROJECT_ID="custom-project"\n';
    await envFile.writeAsString(customEnv);

    final out = StringBuffer();
    final result = await runScaffold(
      args: const [],
      targetDir: tempDir,
      out: out,
      err: StringBuffer(),
    );

    expect(result.exitCode, 0);
    expect(result.createdEnvFile, isFalse);
    expect(await envFile.readAsString(), customEnv);
    expect(out.toString(), contains('Kept existing scripts/firebase_kit.env'));
  });

  test('--check passes when managed files are up to date', () async {
    await runScaffold(
      args: const [],
      targetDir: tempDir,
      out: StringBuffer(),
      err: StringBuffer(),
    );

    final out = StringBuffer();
    final err = StringBuffer();
    final result = await runScaffold(
      args: const ['--check'],
      targetDir: tempDir,
      out: out,
      err: err,
    );

    expect(result.exitCode, 0);
    expect(result.driftedFiles, isEmpty);
    expect(err.toString(), isEmpty);
    expect(
      out.toString(),
      contains('All 5 firebase_kit managed files are up to date'),
    );
  });

  test('--check exits 1 when a managed file is modified or missing', () async {
    await runScaffold(
      args: const [],
      targetDir: tempDir,
      out: StringBuffer(),
      err: StringBuffer(),
    );

    final scriptFile = File('${tempDir.path}/scripts/run_dev.sh');
    await scriptFile.writeAsString('# modified\n');

    final driverFile = File(
      '${tempDir.path}/test_driver/integration_test.dart',
    );
    await driverFile.delete();

    final err = StringBuffer();
    final result = await runScaffold(
      args: const ['--check'],
      targetDir: tempDir,
      out: StringBuffer(),
      err: err,
    );

    expect(result.exitCode, 1);
    expect(
      result.driftedFiles,
      containsAll([
        'scripts/run_dev.sh (modified)',
        'test_driver/integration_test.dart (missing)',
      ]),
    );
    expect(
      err.toString(),
      allOf(
        contains('scripts/run_dev.sh (modified)'),
        contains('test_driver/integration_test.dart (missing)'),
      ),
    );
  });
}
