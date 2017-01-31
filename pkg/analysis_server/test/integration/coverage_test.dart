// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/spec/api.dart';
import '../../tool/spec/from_html.dart';

/// Define tests to fail if no mention in the coverage file.
main() {
  Api api;
  File coverageFile;

  // parse the API file
  if (FileSystemEntity.isFileSync('tool/spec/spec_input.html')) {
    api = readApi('.');
    coverageFile = new File('test/integration/coverage.md');
  } else {
    api = readApi('pkg/analysis_server');
    coverageFile = new File('pkg/analysis_server/test/integration/coverage.md');
  }

  List<String> lines = coverageFile.readAsLinesSync();

  // ## server domain
  Set<String> coveredDomains = lines
      .where((line) => line.startsWith('## ') && line.endsWith(' domain'))
      .map((line) =>
          line.substring('##'.length, line.length - 'domain'.length).trim())
      .toSet();

  // - [ ] server.getVersion
  Set<String> members = lines
      .where((line) => line.startsWith('- '))
      .map((line) => line.substring('- [ ]'.length).trim())
      .toSet();

  // generate domain tests
  for (Domain domain in api.domains) {
    group('integration coverage of ${domain.name}', () {
      // domain
      test('domain', () {
        if (!coveredDomains.contains(domain.name)) {
          fail('${domain.name} domain not found in ${coverageFile.path}');
        }
      });

      // requests
      for (Request request in domain.requests) {
        String name = '${domain.name}.${request.method}';
        test(name, () {
          if (!members.contains(name)) {
            fail('$name not found in ${coverageFile.path}');
          }
        });
      }
    });
  }

  // validate no unexpected domains
  group('integration coverage', () {
    test('no unexpected domains', () {
      for (String domain in coveredDomains) {
        expect(api.domains.map((d) => d.name), contains(domain));
      }
    });
  });
}
