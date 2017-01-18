// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show
    exit,
    exitCode;

import 'package:fasta/src/ast_kind.dart' show
    AstKind;

import 'package:fasta/src/compiler_command_line.dart' show
    CompilerCommandLine;

import 'package:fasta/src/outline.dart' show
    doCompile,
    parseArguments;

import 'package:fasta/src/errors.dart' show
    InputError;

import 'package:fasta/src/run.dart' show
    run;

import 'package:fasta/src/ticker.dart' show
    Ticker;

const int iterations = const int.fromEnvironment("iterations", defaultValue: 1);

main(List<String> arguments) async {
  Uri uri;
  CompilerCommandLine cl;
  for (int i = 0; i < iterations; i++) {
    if (i > 0) {
      print("\n");
    }
    try {
      cl = parseArguments("run", arguments);
      uri =
          await doCompile(cl, new Ticker(isVerbose:cl.verbose), AstKind.Kernel);
    } on InputError catch (e) {
      print(e.format());
      exit(1);
    }
    if (exitCode != 0) exit(exitCode);
  }
  exit(await run(uri, cl));
}
