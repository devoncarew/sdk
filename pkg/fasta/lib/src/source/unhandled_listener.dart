// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.unhandled_listener;

import 'package:dart_scanner/src/token.dart' show
    Token;

import 'stack_listener.dart' show
    NullValue,
    StackListener;

export 'stack_listener.dart' show
    NullValue;

// TODO(ahe): Get rid of this.
enum Unhandled {
  ConditionalUri,
  ConditionalUris,
  DottedName,
  Hide,
  Initializers,
  Interpolation,
  Metadata,
  Show,
  TypeVariables,
}

// TODO(ahe): Get rid of this class when all listeners are complete.
abstract class UnhandledListener extends StackListener {
  void endMetadataStar(int count, bool forParameter) {
    debugEvent("MetadataStar");
    push(popList(count) ?? NullValue.Metadata);
  }

  void endConditionalUri(Token ifKeyword, Token equalitySign) {
    debugEvent("ConditionalUri");
    pop(); // URI.
    popIfNotNull(equalitySign);  // String.
    pop(); // DottedName.
    push(Unhandled.ConditionalUri);
  }

  void endConditionalUris(int count) {
    debugEvent("ConditionalUris");
    popList(count);
    push(Unhandled.ConditionalUris);
  }

  void endHide(Token hideKeyword) {
    debugEvent("Hide");
    pop();
    push(Unhandled.Hide);
  }

  void endShow(Token showKeyword) {
    debugEvent("Show");
    pop();
    push(Unhandled.Show);
  }

  void endCombinators(int count) {
    debugEvent("Combinators");
    push(popList(count) ?? NullValue.Combinators);
  }

  void endDottedName(int count, Token firstIdentifier) {
    debugEvent("DottedName");
    popList(count);
    push(Unhandled.DottedName);
  }
}