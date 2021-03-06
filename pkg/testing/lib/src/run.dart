// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library testing.run;

import 'dart:async' show
    Future,
    Stream;

import 'dart:convert' show
    JSON;

import 'dart:io' show
    Platform;

import 'dart:isolate' show
    Isolate,
    ReceivePort;

import 'test_root.dart' show
    TestRoot;

import 'test_description.dart' show
    TestDescription;

import 'error_handling.dart' show
    withErrorHandling;

import 'chain.dart' show
    CreateContext;

import '../testing.dart' show
    Chain,
    ChainContext,
    TestDescription,
    listTests;

import 'analyze.dart' show
    Analyze;

import 'log.dart' show
    isVerbose,
    logMessage,
    logNumberedLines,
    splitLines;

import 'suite.dart' show
    Dart,
    Suite;

import 'zone_helper.dart' show
    acknowledgeControlMessages;

Future<TestRoot> computeTestRoot(String configurationPath, Uri base) {
  Uri configuration = configurationPath == null
      ? Uri.base.resolve("testing.json")
      : base.resolve(configurationPath);
  return TestRoot.fromUri(configuration);
}

/// This is called from a Chain suite, and helps implement main. In most cases,
/// main will look like this:
///
///     main(List<String> arguments) => runMe(arguments, createContext);
///
/// The optional argument [configurationPath] should be used when
/// `testing.json` isn't located in the current working directory and is a path
/// relative to `Platform.script`.
Future<Null> runMe(
    List<String> arguments, CreateContext f, [String configurationPath]) {
  return withErrorHandling(() async {
    TestRoot testRoot =
        await computeTestRoot(configurationPath, Platform.script);
    for (Chain suite in testRoot.toolChains) {
      if (Platform.script == suite.source) {
        print("Running suite ${suite.name}...");
        ChainContext context = await f(suite, <String, String>{});
        await context.run(suite, new Set<String>());
      }
    }
  });
}

/// This is called from a `_test.dart` file, and helps integration in other
/// test runner frameworks.
///
/// For example, to run the suite `my_suite` from `test.dart`, create a file
/// with this content:
///
///     import 'package:async_helper/async_helper.dart' show asyncTest;
///
///     import 'package:testing/testing.dart' show run;
///
///     main(List<String> arguments) => asyncTest(run(arguments, ["my_suite"]));
///
/// To run run the same suite from `package:test`, create a file with this
/// content:
///
///     import 'package:test/test.dart' show Timeout, test;
///
///     import 'package:testing/testing.dart' show run;
///
///     main() {
///       test("my_suite", () => run([], ["my_suite"]),
///           timeout: new Timeout(new Duration(minutes: 5)));
///     }
///
/// The optional argument [configurationPath] should be used when
/// `testing.json` isn't located in the current working directory and is a path
/// relative to `Uri.base`.
Future<Null> run(
    List<String> arguments, List<String> suiteNames,
    [String configurationPath]) {
  return withErrorHandling(() async {
    TestRoot root = await computeTestRoot(configurationPath, Uri.base);
    List<Suite> suites = root.suites.where(
        (Suite suite) => suiteNames.contains(suite.name)).toList();
    SuiteRunner runner = new SuiteRunner(suites, <String, String>{}, null);
    String program = await runner.generateDartProgram();
    await runner.analyze(root.packages);
    if (program != null) {
      await runProgram(program, root.packages);
    }
  });
}

Future<Null> runProgram(String program, Uri packages) async {
  logMessage("Running:");
  logNumberedLines(program);
  Uri dataUri = new Uri.dataFromString(program);
  ReceivePort exitPort = new ReceivePort();
  Isolate isolate = await Isolate.spawnUri(dataUri, <String>[], null,
      paused: true, onExit: exitPort.sendPort, errorsAreFatal: false,
      checked: true, packageConfig: packages);
  List error;
  var subscription = isolate.errors.listen((data) {
    error = data;
    exitPort.close();
  });
  await acknowledgeControlMessages(isolate, resume: isolate.pauseCapability);
  await for (var _ in exitPort) {
    exitPort.close();
  }
  subscription.cancel();
  return error == null
      ? null
      : new Future<Null>.error(error[0], new StackTrace.fromString(error[1]));
}

class SuiteRunner {
  final List<Suite> suites;

  final Map<String, String> environment;

  final List<String> selectors;

  List<Uri> testUris;

  SuiteRunner(this.suites, this.environment, Iterable<String> selectors)
      : selectors = selectors.toList(growable: false);

  Future<String> generateDartProgram() async {
    List<TestDescription> descriptions = await list().toList();
    testUris = <Uri>[];
    StringBuffer imports = new StringBuffer();
    StringBuffer dart = new StringBuffer();
    StringBuffer chain = new StringBuffer();

    for (TestDescription description in descriptions) {
      testUris.add(await Isolate.resolvePackageUri(description.uri));
      description.writeImportOn(imports);
      description.writeClosureOn(dart);
    }

    for (Chain suite in suites.where((Suite suite) => suite is Chain)) {
      testUris.add(await Isolate.resolvePackageUri(suite.source));
      suite.writeImportOn(imports);
      suite.writeClosureOn(chain);
    }

    if (testUris.isEmpty) return null;

    return """
library testing.generated;

import 'dart:async' show Future;

import 'dart:convert' show JSON;

import 'package:testing/src/run_tests.dart' show runTests;

import 'package:testing/src/chain.dart' show runChain;

import 'package:testing/src/log.dart' show enableVerboseOutput, isVerbose;

${imports.toString().trim()}

Future<Null> main() async {
  if ($isVerbose) enableVerboseOutput();
  Map<String, String> environment = JSON.decode('${JSON.encode(environment)}');
  Set<String> selectors = JSON.decode('${JSON.encode(selectors)}').toSet();
  await runTests(<String, Function> {
      ${splitLines(dart.toString().trim()).join('      ')}
  });
  ${splitLines(chain.toString().trim()).join('  ')}
}
""";
  }

  Future<Null> analyze(Uri packages) async {
    for (Analyze suite in suites.where((Suite suite) => suite is Analyze)) {
      await suite.run(packages, testUris);
    }
  }

  Stream<TestDescription> list() async* {
    for (Dart suite in suites.where((Suite suite) => suite is Dart)) {
      await for (TestDescription description in
                     listTests(<Uri>[suite.uri], pattern: "")) {
        String path = description.file.uri.path;
        if (suite.exclude.any((RegExp r) => path.contains(r))) continue;
        if (suite.pattern.any((RegExp r) => path.contains(r))) {
          yield description;
        }
      }
    }
  }
}
