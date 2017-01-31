// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js.scanner.string_scanner;

import 'array_based_scanner.dart' show
    ArrayBasedScanner;

import 'precedence.dart' show
    PrecedenceInfo;

import 'token.dart' show
    StringToken,
    Token;

/**
 * Scanner that reads from a String and creates tokens that points to
 * substrings.
 */
class StringScanner extends ArrayBasedScanner {
  /** The file content. */
  String string;

  /** The current offset in [string]. */
  int scanOffset = -1;

  StringScanner(String string, {bool includeComments: false})
      : string = ensureZeroTermination(string),
        super(includeComments);

  static String ensureZeroTermination(String string) {
    return (string.isEmpty || string.codeUnitAt(string.length - 1) != 0)
        // TODO(lry): abort instead of copying the array, or warn?
        ? string + '\x00'
        : string;
  }

  int advance() => string.codeUnitAt(++scanOffset);
  int peek() => string.codeUnitAt(scanOffset + 1);

  int get stringOffset => scanOffset;

  int currentAsUnicode(int next) => next;

  void handleUnicode(int startScanOffset) {}

  Token firstToken() => tokens.next;
  Token previousToken() => tail;

  void appendSubstringToken(PrecedenceInfo info, int start, bool asciiOnly,
      [int extraOffset = 0]) {
    tail.next = new StringToken.fromSubstring(
        info, string, start, scanOffset + extraOffset, tokenStart,
        canonicalize: true);
    tail = tail.next;
  }

  bool atEndOfFile() => scanOffset >= string.length - 1;
}
