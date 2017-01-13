// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

import 'package:testing/testing.dart';

import 'package:scanner/scanner.dart';

import 'package:scanner/io.dart';

class Read extends Step<TestDescription, List<int>, ChainContext> {
  const Read();

  String get name => "read";

  Future<Result<List<int>>> run(
      TestDescription input, ChainContext context) async {
    return pass(await readBytesFromFile(input.uri));
  }
}

class Scan extends Step<List<int>, ScannerResult, ChainContext> {
  const Scan();

  String get name => "scan";

  Future<Result<ScannerResult>> run(
      List<int> bytes, ChainContext context) async {
    return pass(scan(bytes));
  }
}
