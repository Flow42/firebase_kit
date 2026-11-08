import 'dart:io';

import 'package:firebase_kit/src/scaffold/scaffold_runner.dart';

Future<void> main(List<String> args) async {
  final result = await runScaffold(args: args);
  exitCode = result.exitCode;
}
