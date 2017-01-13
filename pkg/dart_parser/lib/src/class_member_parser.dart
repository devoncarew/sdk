// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart_parser.class_member_parser;

import 'package:dart_scanner/src/token.dart' show
    BeginGroupToken,
    ErrorToken,
    Token;

import 'package:dart_scanner/src/token_constants.dart' show
    EOF_TOKEN;

import 'listener.dart' show
    Listener;

import 'error_kind.dart' show
    ErrorKind;

import 'parser.dart' show
    Parser,
    optional;

/// Parser similar to [TopLevelParser] but also parses class members (excluding
/// their bodies).
class ClassMemberParser extends Parser {
  ClassMemberParser(Listener listener,
      {bool asyncAwaitKeywordsEnabled: false,
       bool enableGenericMethodSyntax: false})
      : super(listener, asyncAwaitKeywordsEnabled: asyncAwaitKeywordsEnabled,
          enableGenericMethodSyntax: enableGenericMethodSyntax);

  Token parseExpression(Token token) => skipExpression(token);

  Token parseArgumentsOpt(Token token) {
    // This method is overridden for two reasons:
    // 1. Avoid generating events for arguments.
    // 2. Avoid calling skip expression for each argument (which doesn't work).
    listener.handleNoArguments(token);
    if (optional('(', token)) {
      BeginGroupToken begin = token;
      return begin.endGroup.next;
    } else {
      return token;
    }
  }

  Token skipExpression(Token token) {
    while (true) {
      final kind = token.kind;
      final value = token.stringValue;
      if ((identical(kind, EOF_TOKEN)) ||
          (identical(value, ';')) ||
          (identical(value, ',')) ||
          (identical(value, '}')) ||
          (identical(value, ')')) ||
          (identical(value, ']'))) {
        break;
      }
      if (identical(value, '=') ||
          identical(value, '?') ||
          identical(value, ':') ||
          identical(value, '??')) {
        var nextValue = token.next.stringValue;
        if (identical(nextValue, 'const')) {
          token = token.next;
          nextValue = token.next.stringValue;
        }
        if (identical(nextValue, '{')) {
          // Handle cases like this:
          // class Foo {
          //   var map;
          //   Foo() : map = {};
          //   Foo.x() : map = true ? {} : {};
          // }
          BeginGroupToken begin = token.next;
          token = (begin.endGroup != null) ? begin.endGroup : token;
          token = token.next;
          continue;
        }
        if (identical(nextValue, '<')) {
          // Handle cases like this:
          // class Foo {
          //   var map;
          //   Foo() : map = <String, Foo>{};
          //   Foo.x() : map = true ? <String, Foo>{} : <String, Foo>{};
          // }
          BeginGroupToken begin = token.next;
          token = (begin.endGroup != null) ? begin.endGroup : token;
          token = token.next;
          if (identical(token.stringValue, '{')) {
            begin = token;
            token = (begin.endGroup != null) ? begin.endGroup : token;
            token = token.next;
          }
          continue;
        }
      }
      if (!mayParseFunctionExpressions && identical(value, '{')) {
        break;
      }
      if (token is BeginGroupToken) {
        BeginGroupToken begin = token;
        token = (begin.endGroup != null) ? begin.endGroup : token;
      } else if (token is ErrorToken) {
        listener.reportErrorToken(token);
      }
      token = token.next;
    }
    return token;
  }

  Token skipAsyncModifier(Token token) {
    String value = token.stringValue;
    if (identical(value, 'async')) {
      token = token.next;
      value = token.stringValue;

      if (identical(value, '*')) {
        token = token.next;
      }
    } else if (identical(value, 'sync')) {
      token = token.next;
      value = token.stringValue;

      if (identical(value, '*')) {
        token = token.next;
      }
    }
    return token;
  }

  Token parseFunctionBody(Token token, bool isExpression, bool allowAbstract) {
    assert(!isExpression);
    token = skipAsyncModifier(token);
    String value = token.stringValue;
    if (identical(value, ';')) {
      if (!allowAbstract) {
        listener.reportError(token, ErrorKind.EXPECTED_BODY);
      }
      listener.handleNoFunctionBody(token);
    } else {
      if (identical(value, '=>')) {
        token = parseExpression(token.next);
        expectSemicolon(token);
      } else if (value == '=') {
        token = parseRedirectingFactoryBody(token);
        expectSemicolon(token);
      } else {
        token = skipBlock(token);
      }
      listener.skippedFunctionBody(token);
    }
    return token;
  }
}
