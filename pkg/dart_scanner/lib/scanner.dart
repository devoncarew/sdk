// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library dart_scanner;

import 'src/token.dart' show
    Token;

import 'src/utf8_bytes_scanner.dart' show
    Utf8BytesScanner;

abstract class Scanner {
  List<int> get lineStarts;
  Token tokenize();
}

class ScannerResult {
  final Token tokens;
  final List<int> lineStarts;

  ScannerResult(this.tokens, this.lineStarts);
}

ScannerResult scan(List<int> bytes, {bool includeComments: false}) {
  if (bytes.last != 0) {
    throw new ArgumentError("[bytes]: the last byte must be null.");
  }
  Scanner scanner =
      new Utf8BytesScanner(bytes, includeComments: includeComments);
  return new ScannerResult(scanner.tokenize(), scanner.lineStarts);
}
