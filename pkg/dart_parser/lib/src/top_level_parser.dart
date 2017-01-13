// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library parser.top_level_parser;

import 'package:scanner/src/token.dart' show
    BeginGroupToken,
    Token;

import 'package:scanner/src/characters.dart' show
    $CLOSE_CURLY_BRACKET;

import 'listener.dart' show
    Listener;

import 'class_member_parser.dart' show
    ClassMemberParser;

import 'parser.dart' show
    optional;

/// Parser which only parses top-level elements, but ignores their bodies.
/// Use [Parser] to parse everything.
class TopLevelParser extends ClassMemberParser {
  TopLevelParser(Listener listener,
      {bool asyncAwaitKeywordsEnabled: false,
       bool enableGenericMethodSyntax: false})
      : super(listener, asyncAwaitKeywordsEnabled: asyncAwaitKeywordsEnabled,
          enableGenericMethodSyntax: enableGenericMethodSyntax);

  Token parseClassBody(Token token) {
    if (!optional('{', token)) {
      return listener.expectedClassBodyToSkip(token);
    }
    BeginGroupToken beginGroupToken = token;
    Token endGroup = beginGroupToken.endGroup;
    if (endGroup == null) {
      return listener.unmatched(beginGroupToken);
    } else if (!identical(endGroup.kind, $CLOSE_CURLY_BRACKET)) {
      return listener.unmatched(beginGroupToken);
    }
    return endGroup;
  }
}
