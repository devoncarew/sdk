// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library testing.abstract_context;

import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/visitor.dart';
import 'package:analyzer/exception/exception.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:analyzer/source/package_map_resolver.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/dart/analysis/file_state.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/engine.dart' as engine;
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/source_io.dart';

import 'mock_sdk.dart';

/**
 * Finds an [Element] with the given [name].
 */
Element findChildElement(Element root, String name, [ElementKind kind]) {
  Element result = null;
  root.accept(new _ElementVisitorFunctionWrapper((Element element) {
    if (element.name != name) {
      return;
    }
    if (kind != null && element.kind != kind) {
      return;
    }
    result = element;
  }));
  return result;
}

/**
 * A function to be called for every [Element].
 */
typedef void _ElementVisitorFunction(Element element);

class AbstractContextTest {
  MemoryResourceProvider provider;
  DartSdk sdk;
  Map<String, List<Folder>> packageMap;
  UriResolver resourceResolver;

  AnalysisContext _context;

  StringBuffer _logBuffer = new StringBuffer();
  FileContentOverlay _fileContentOverlay = new FileContentOverlay();
  AnalysisDriver _driver;

  AnalysisContext get context {
    if (enableNewAnalysisDriver) {
      throw new StateError('Should not be used with the new analysis driver.');
    }
    return _context;
  }

  AnalysisDriver get driver {
    if (enableNewAnalysisDriver) {
      return _driver;
    }
    throw new StateError('Should be used with the new analysis driver.');
  }

  /**
   * Return `true` if the new analysis driver should be used by these tests.
   */
  bool get enableNewAnalysisDriver => false;

  Source addPackageSource(String packageName, String filePath, String content) {
    packageMap[packageName] = [(newFolder('/pubcache/$packageName'))];
    File file = newFile('/pubcache/$packageName/$filePath', content);
    return file.createSource();
  }

  Source addSource(String path, String content, [Uri uri]) {
    File file = newFile(path, content);
    if (enableNewAnalysisDriver) {
      driver.addFile(path);
      _fileContentOverlay[path] = content;
      return null;
    } else {
      Source source = file.createSource(uri);
      ChangeSet changeSet = new ChangeSet();
      changeSet.addedSource(source);
      context.applyChanges(changeSet);
      context.setContents(source, content);
      return source;
    }
  }

  File newFile(String path, [String content]) =>
      provider.newFile(provider.convertPath(path), content ?? '');

  Folder newFolder(String path) =>
      provider.newFolder(provider.convertPath(path));

  /**
   * Performs all analysis tasks in [context].
   */
  void performAllAnalysisTasks() {
    if (enableNewAnalysisDriver) {
      return;
    }
    while (true) {
      engine.AnalysisResult result = context.performAnalysisTask();
      if (!result.hasMoreWork) {
        break;
      }
    }
  }

  void processRequiredPlugins() {
    AnalysisEngine.instance.processRequiredPlugins();
  }

  Future<CompilationUnit> resolveLibraryUnit(Source source) async {
    if (enableNewAnalysisDriver) {
      return (await driver.getResult(source.fullName))?.unit;
    } else {
      return context.resolveCompilationUnit2(source, source);
    }
  }

  void setUp() {
    processRequiredPlugins();
    setupResourceProvider();
    sdk = new MockSdk(resourceProvider: provider);
    resourceResolver = new ResourceUriResolver(provider);
    packageMap = new Map<String, List<Folder>>();
    PackageMapUriResolver packageResolver =
        new PackageMapUriResolver(provider, packageMap);
    SourceFactory sourceFactory = new SourceFactory(
        [new DartUriResolver(sdk), packageResolver, resourceResolver]);
    if (enableNewAnalysisDriver) {
      PerformanceLog log = new PerformanceLog(_logBuffer);
      AnalysisDriverScheduler scheduler = new AnalysisDriverScheduler(log);
      _driver = new AnalysisDriver(
          scheduler,
          log,
          provider,
          new MemoryByteStore(),
          _fileContentOverlay,
          'test',
          sourceFactory,
          new AnalysisOptionsImpl());
      scheduler.start();
    } else {
      _context = AnalysisEngine.instance.createAnalysisContext();
      context.sourceFactory = sourceFactory;
    }
    AnalysisEngine.instance.logger = PrintLogger.instance;
  }

  void setupResourceProvider() {
    provider = new MemoryResourceProvider();
  }

  void tearDown() {
    _context = null;
    provider = null;
    AnalysisEngine.instance.clearCaches();
    AnalysisEngine.instance.logger = null;
  }
}

/**
 * Instances of the class [PrintLogger] print all of the errors.
 */
class PrintLogger implements Logger {
  static final Logger instance = new PrintLogger();

  @override
  void logError(String message, [CaughtException exception]) {
    print(message);
    if (exception != null) {
      print(exception);
    }
  }

  @override
  void logInformation(String message, [CaughtException exception]) {
    print(message);
    if (exception != null) {
      print(exception);
    }
  }
}

/**
 * Wraps the given [_ElementVisitorFunction] into an instance of
 * [engine.GeneralizingElementVisitor].
 */
class _ElementVisitorFunctionWrapper extends GeneralizingElementVisitor {
  final _ElementVisitorFunction function;
  _ElementVisitorFunctionWrapper(this.function);
  visitElement(Element element) {
    function(element);
    super.visitElement(element);
  }
}
