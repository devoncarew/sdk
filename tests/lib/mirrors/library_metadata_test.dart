// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@string @symbol
library test.library_metadata_test;

import 'dart:mirrors';

const string = 'a metadata string';

const symbol = const Symbol('symbol');

const hest = 'hest';

checkMetadata(DeclarationMirror mirror, List expectedMetadata) {
  List metadata = mirror.metadata.map((m) => m.reflectee).toList();
  if (metadata == null) {
    throw 'Null metadata on $mirror';
  }
  int expectedLength = expectedMetadata.length;
  int actualLength = metadata.length;
  if (expectedLength != actualLength) {
    throw 'Expected length = $expectedLength, but got length = $actualLength.';
  }
  for (int i = 0; i < expectedLength; i++) {
    if (metadata[i] != expectedMetadata[i]) {
      throw '${metadata[i]} is not "${expectedMetadata[i]}"'
          ' in $mirror at index $i';
    }
  }
  print(metadata);
}

main() {
  if (MirrorSystem.getName(symbol) != 'symbol') {
    // This happened in dart2js due to how early library metadata is
    // computed.
    throw 'Bad constant: $symbol';
  }

  MirrorSystem mirrors = currentMirrorSystem();
  checkMetadata(mirrors.findLibrary(const Symbol('test.library_metadata_test')).first,
                [string, symbol]); 
}
