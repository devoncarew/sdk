// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:developer' show debugger;

import 'dart:convert' show jsonDecode;

import 'dart:io' show Directory, File;

import 'package:_fe_analyzer_shared/src/messages/diagnostic_message.dart'
    show DiagnosticMessage, getMessageCodeObject;

import 'package:_fe_analyzer_shared/src/util/colors.dart' as colors;

import 'package:_fe_analyzer_shared/src/messages/severity.dart' show Severity;

import 'package:compiler/src/kernel/dart2js_target.dart' show Dart2jsTarget;

import "package:dev_compiler/src/kernel/target.dart" show DevCompilerTarget;

import 'package:expect/expect.dart' show Expect;

import 'package:front_end/src/api_prototype/compiler_options.dart'
    show CompilerOptions, parseExperimentalArguments, parseExperimentalFlags;

import 'package:front_end/src/api_prototype/experimental_flags.dart'
    show ExperimentalFlag;
import 'package:front_end/src/api_prototype/incremental_kernel_generator.dart'
    show IncrementalCompilerResult;
import "package:front_end/src/api_prototype/memory_file_system.dart"
    show MemoryFileSystem, MemoryFileSystemEntity;

import 'package:front_end/src/base/nnbd_mode.dart' show NnbdMode;

import 'package:front_end/src/base/processed_options.dart'
    show ProcessedOptions;

import 'package:front_end/src/compute_platform_binaries_location.dart'
    show computePlatformBinariesLocation, computePlatformDillName;

import 'package:front_end/src/fasta/compiler_context.dart' show CompilerContext;

import 'package:front_end/src/fasta/fasta_codes.dart'
    show DiagnosticMessageFromJson, FormattedMessage;

import 'package:front_end/src/fasta/incremental_compiler.dart'
    show IncrementalCompiler, RecorderForTesting;

import 'package:front_end/src/fasta/incremental_serializer.dart'
    show IncrementalSerializer;

import 'package:front_end/src/fasta/kernel/utils.dart' show ByteSink;

import 'package:kernel/ast.dart';

import 'package:kernel/binary/ast_from_binary.dart' show BinaryBuilder;

import 'package:kernel/binary/ast_to_binary.dart' show BinaryPrinter;

import 'package:kernel/class_hierarchy.dart'
    show ClassHierarchy, ClosedWorldClassHierarchy, ForTestingClassInfo;

import 'package:kernel/src/equivalence.dart'
    show
        EquivalenceResult,
        EquivalenceStrategy,
        EquivalenceVisitor,
        checkEquivalence;

import 'package:kernel/target/targets.dart'
    show
        LateLowering,
        NoneTarget,
        Target,
        TargetFlags,
        TestTargetFlags,
        TestTargetWrapper;

import 'package:kernel/text/ast_to_text.dart'
    show NameSystem, Printer, componentToString;

import "package:testing/testing.dart"
    show
        Chain,
        ChainContext,
        Expectation,
        ExpectationSet,
        Result,
        Step,
        TestDescription,
        runMe;

import "package:vm/target/vm.dart" show VmTarget;

import "package:yaml/yaml.dart" show YamlList, YamlMap, loadYamlNode;

import 'binary_md_dill_reader.dart' show DillComparer;

import "incremental_utils.dart" as util;

import 'testing_utils.dart' show checkEnvironment;

import 'utils/io_utils.dart' show computeRepoDir;

void main([List<String> arguments = const []]) =>
    runMe(arguments, createContext, configurationPath: "../testing.json");

final ExpectationSet staticExpectationSet =
    new ExpectationSet.fromJsonList(jsonDecode(EXPECTATIONS));

const String EXPECTATIONS = '''
[
  {
    "name": "ExpectationFileMismatch",
    "group": "Fail"
  },
  {
    "name": "ExpectationFileMissing",
    "group": "Fail"
  },
  {
    "name": "MissingErrors",
    "group": "Fail"
  },
  {
    "name": "UnexpectedErrors",
    "group": "Fail"
  },
  {
    "name": "MissingWarnings",
    "group": "Fail"
  },
  {
    "name": "UnexpectedWarnings",
    "group": "Fail"
  },
  {
    "name": "ClassHierarchyError",
    "group": "Fail"
  },
  {
    "name": "NeededDillMismatch",
    "group": "Fail"
  },
  {
    "name": "IncrementalSerializationError",
    "group": "Fail"
  },
  {
    "name": "ContentDataMismatch",
    "group": "Fail"
  },
  {
    "name": "MissingInitializationError",
    "group": "Fail"
  },
  {
    "name": "UnexpectedInitializationError",
    "group": "Fail"
  },
  {
    "name": "ReachableLibrariesError",
    "group": "Fail"
  },
  {
    "name": "EquivalenceError",
    "group": "Fail"
  },
  {
    "name": "UriToSourceError",
    "group": "Fail"
  },
  {
    "name": "MissingPlatformLibraries",
    "group": "Fail"
  },
  {
    "name": "UnexpectedPlatformLibraries",
    "group": "Fail"
  },
  {
    "name": "UnexpectedRebuildBodiesOnly",
    "group": "Fail"
  },
  {
    "name": "UnexpectedEntryToLibraryCount",
    "group": "Fail"
  },
  {
    "name": "LibraryCountMismatch",
    "group": "Fail"
  },
  {
    "name": "InitializedFromDillMismatch",
    "group": "Fail"
  },
  {
    "name": "NNBDModeMismatch",
    "group": "Fail"
  }
]
''';

final Expectation ExpectationFileMismatch =
    staticExpectationSet["ExpectationFileMismatch"];
final Expectation ExpectationFileMissing =
    staticExpectationSet["ExpectationFileMissing"];
final Expectation MissingErrors = staticExpectationSet["MissingErrors"];
final Expectation UnexpectedErrors = staticExpectationSet["UnexpectedErrors"];
final Expectation MissingWarnings = staticExpectationSet["MissingWarnings"];
final Expectation UnexpectedWarnings =
    staticExpectationSet["UnexpectedWarnings"];
final Expectation ClassHierarchyError =
    staticExpectationSet["ClassHierarchyError"];
final Expectation NeededDillMismatch =
    staticExpectationSet["NeededDillMismatch"];
final Expectation IncrementalSerializationError =
    staticExpectationSet["IncrementalSerializationError"];
final Expectation ContentDataMismatch =
    staticExpectationSet["ContentDataMismatch"];
final Expectation MissingInitializationError =
    staticExpectationSet["MissingInitializationError"];
final Expectation UnexpectedInitializationError =
    staticExpectationSet["UnexpectedInitializationError"];
final Expectation ReachableLibrariesError =
    staticExpectationSet["ReachableLibrariesError"];
final Expectation EquivalenceError = staticExpectationSet["EquivalenceError"];
final Expectation UriToSourceError = staticExpectationSet["UriToSourceError"];
final Expectation MissingPlatformLibraries =
    staticExpectationSet["MissingPlatformLibraries"];
final Expectation UnexpectedPlatformLibraries =
    staticExpectationSet["UnexpectedPlatformLibraries"];
final Expectation UnexpectedRebuildBodiesOnly =
    staticExpectationSet["UnexpectedRebuildBodiesOnly"];
final Expectation UnexpectedEntryToLibraryCount =
    staticExpectationSet["UnexpectedEntryToLibraryCount"];
final Expectation LibraryCountMismatch =
    staticExpectationSet["LibraryCountMismatch"];
final Expectation InitializedFromDillMismatch =
    staticExpectationSet["InitializedFromDillMismatch"];
final Expectation NNBDModeMismatch = staticExpectationSet["NNBDModeMismatch"];

Future<Context> createContext(Chain suite, Map<String, String> environment) {
  const Set<String> knownEnvironmentKeys = {
    "updateExpectations",
    "addDebugBreaks",
    "skipTests",
  };
  checkEnvironment(environment, knownEnvironmentKeys);

  // Disable colors to ensure that expectation files are the same across
  // platforms and independent of stdin/stderr.
  colors.enableColors = false;
  Set<String> skipTests = environment["skipTests"]?.split(",").toSet() ?? {};
  return new Future.value(new Context(
    environment["updateExpectations"] == "true",
    environment["addDebugBreaks"] == "true",
    skipTests,
  ));
}

class Context extends ChainContext {
  @override
  final List<Step> steps = const <Step>[
    const ReadTest(),
    const RunCompilations(),
  ];

  final bool updateExpectations;

  /// Add a debug break (via dart:developers `debugger()` call) after each
  /// iteration (or 'world run') when doing a "new world test".
  final bool breakBetween;

  final Set<String> skipTests;

  Context(this.updateExpectations, this.breakBetween, this.skipTests);

  @override
  Stream<TestDescription> list(Chain suite) {
    if (skipTests.isEmpty) return super.list(suite);
    return filterSkipped(super.list(suite));
  }

  Stream<TestDescription> filterSkipped(Stream<TestDescription> all) async* {
    await for (TestDescription testDescription in all) {
      if (!skipTests.contains(testDescription.shortName)) {
        yield testDescription;
      }
    }
  }

  @override
  Future<void> cleanUp(TestDescription description, Result result) async {
    await cleanupHelper?.outDir?.delete(recursive: true);
    cleanupHelper?.outDir = null;
  }

  @override
  final ExpectationSet expectationSet = staticExpectationSet;

  TestData? cleanupHelper;
}

class TestData {
  YamlMap map;
  Directory? outDir;
  Uri loadedFrom;

  TestData(this.map, this.outDir, this.loadedFrom);
}

class ReadTest extends Step<TestDescription, TestData, Context> {
  const ReadTest();

  @override
  String get name => "read test";

  @override
  Future<Result<TestData>> run(
      TestDescription description, Context context) async {
    Uri uri = description.uri;
    String contents = await new File.fromUri(uri).readAsString();
    TestData data = new TestData(
        loadYamlNode(contents, sourceUrl: uri) as YamlMap,
        Directory.systemTemp.createTempSync("incremental_load_from_dill_test"),
        uri);
    context.cleanupHelper = data;
    return pass(data);
  }
}

class RunCompilations extends Step<TestData, TestData, Context> {
  const RunCompilations();

  @override
  String get name => "run compilations";

  @override
  Future<Result<TestData>> run(TestData data, Context context) async {
    Result<TestData>? result;
    YamlMap map = data.map;
    Set<String> keys = new Set<String>.from(map.keys.cast<String>());
    keys.remove("type");
    switch (map["type"]) {
      case "basic":
        keys.removeAll(["sources", "entry", "invalidate"]);
        await basicTest(
          map["sources"],
          map["entry"],
          map["invalidate"],
          data.outDir!,
        );
        break;
      case "newworld":
        keys.removeAll([
          "worlds",
          "modules",
          "omitPlatform",
          "target",
          "forceLateLoweringForTesting",
          "trackWidgetCreation",
          "incrementalSerialization",
          "nnbdMode",
        ]);
        result = await new NewWorldTest().newWorldTest(
          data,
          context,
          map["worlds"],
          map["modules"],
          map["omitPlatform"],
          map["target"],
          map["forceLateLoweringForTesting"] ?? false,
          map["trackWidgetCreation"] ?? false,
          map["incrementalSerialization"],
          map["nnbdMode"] == "strong" ? NnbdMode.Strong : NnbdMode.Weak,
        );
        break;
      default:
        throw "Unexpected type: ${map['type']}";
    }

    if (keys.isNotEmpty) throw "Unknown toplevel keys: $keys";
    return result ?? pass(data);
  }
}

Future<Null> basicTest(YamlMap sourceFiles, String entryPoint,
    YamlList? invalidate, Directory outDir) async {
  Uri entryPointUri = outDir.uri.resolve(entryPoint);
  Set<String> invalidateFilenames =
      invalidate == null ? new Set<String>() : new Set<String>.from(invalidate);
  List<Uri> invalidateUris = <Uri>[];
  Uri? packagesUri;
  for (String filename in sourceFiles.keys) {
    Uri uri = outDir.uri.resolve(filename);
    if (invalidateFilenames.contains(filename)) {
      invalidateUris.add(uri);
      invalidateFilenames.remove(filename);
    }
    String source = sourceFiles[filename];
    if (filename == ".dart_tool/package_config.json") {
      packagesUri = uri;
    }
    File file = new File.fromUri(uri);
    await file.parent.create(recursive: true);
    await file.writeAsString(source);
  }
  for (String invalidateFilename in invalidateFilenames) {
    if (invalidateFilename.startsWith('package:')) {
      invalidateUris.add(Uri.parse(invalidateFilename));
    } else {
      throw "Error in test yaml: $invalidateFilename was not recognized.";
    }
  }

  Uri output = outDir.uri.resolve("full.dill");
  Uri initializedOutput = outDir.uri.resolve("full_from_initialized.dill");

  Stopwatch stopwatch = new Stopwatch()..start();
  CompilerOptions options = getOptions();
  if (packagesUri != null) {
    options.packagesFileUri = packagesUri;
  }
  await normalCompile(entryPointUri, output, options: options);
  print("Normal compile took ${stopwatch.elapsedMilliseconds} ms");

  stopwatch.reset();
  options = getOptions();
  if (packagesUri != null) {
    options.packagesFileUri = packagesUri;
  }
  bool initializedResult = await initializedCompile(
      entryPointUri, initializedOutput, output, invalidateUris,
      options: options);
  print("Initialized compile(s) from ${output.pathSegments.last} "
      "took ${stopwatch.elapsedMilliseconds} ms");
  Expect.isTrue(initializedResult);

  // Compare the two files.
  List<int> normalDillData = new File.fromUri(output).readAsBytesSync();
  List<int> initializedDillData =
      new File.fromUri(initializedOutput).readAsBytesSync();
  checkIsEqual(normalDillData, initializedDillData);
}

Future<Map<String, List<int>>> createModules(
    Map module,
    final List<int> sdkSummaryData,
    Target target,
    Target originalTarget,
    String sdkSummary,
    {required bool trackNeededDillLibraries}) async {
  final Uri base = Uri.parse("org-dartlang-test:///");
  final Uri sdkSummaryUri = base.resolve(sdkSummary);

  TestMemoryFileSystem fs = new TestMemoryFileSystem(base);
  fs.entityForUri(sdkSummaryUri).writeAsBytesSync(sdkSummaryData);

  // Setup all sources
  for (Map moduleSources in module.values) {
    for (String filename in moduleSources.keys) {
      String data = moduleSources[filename];
      Uri uri = base.resolve(filename);
      if (await fs.entityForUri(uri).exists()) {
        throw "More than one entry for $filename";
      }
      fs.entityForUri(uri).writeAsStringSync(data);
    }
  }

  Map<String, List<int>> moduleResult = new Map<String, List<int>>();

  for (String moduleName in module.keys) {
    List<Uri> moduleSources = <Uri>[];
    Uri? packagesUri;
    for (String filename in module[moduleName].keys) {
      Uri uri = base.resolve(filename);
      if (uri.pathSegments.last == "package_config.json") {
        packagesUri = uri;
      } else {
        moduleSources.add(uri);
      }
    }
    bool outlineOnly = false;
    if (originalTarget is DevCompilerTarget) {
      outlineOnly = true;
    }
    CompilerOptions options =
        getOptions(target: target, sdkSummary: sdkSummary);
    options.fileSystem = fs;
    options.sdkRoot = null;
    options.sdkSummary = sdkSummaryUri;
    options.omitPlatform = true;
    options.onDiagnostic = (DiagnosticMessage message) {
      throw message.ansiFormatted;
    };
    if (packagesUri != null) {
      options.packagesFileUri = packagesUri;
    }
    TestIncrementalCompiler compiler = new TestIncrementalCompiler(
        options, moduleSources.first, /* initializeFrom = */ null, outlineOnly);
    IncrementalCompilerResult? compilerResult = await compiler.computeDelta(
        entryPoints: moduleSources,
        trackNeededDillLibraries: trackNeededDillLibraries);
    Component c = compilerResult.component;
    compilerResult = null;
    c.computeCanonicalNames();
    List<Library> wantedLibs = <Library>[];
    for (Library lib in c.libraries) {
      if (moduleSources.contains(lib.importUri) ||
          moduleSources.contains(lib.fileUri)) {
        wantedLibs.add(lib);
      }
    }
    if (wantedLibs.length != moduleSources.length) {
      throw "Module probably not setup right.";
    }
    Component result = new Component(libraries: wantedLibs)
      ..setMainMethodAndMode(null, false, c.mode);
    List<int> resultBytes = util.postProcess(result);
    moduleResult[moduleName] = resultBytes;
  }

  return moduleResult;
}

class NewWorldTest {
  // These are fields in a class to make it easier to track down memory leaks
  // via the leak detector test.
  Component? newestWholeComponent;
  Component? sdk;
  Component? component;
  Component? component2;
  Component? component3;

  String doStringReplacements(String input) {
    Version enableNonNullableVersion =
        ExperimentalFlag.nonNullable.experimentEnabledVersion;
    String output = input.replaceAll("%NNBD_VERSION_MARKER%",
        "${enableNonNullableVersion.major}.${enableNonNullableVersion.minor}");
    return output;
  }

  Future<Result<TestData>> newWorldTest(
      TestData data,
      Context context,
      List worlds,
      Map? modules,
      bool? omitPlatform,
      String? targetName,
      bool forceLateLoweringForTesting,
      bool trackWidgetCreation,
      bool? incrementalSerialization,
      NnbdMode nnbdMode) async {
    final Uri sdkRoot = computePlatformBinariesLocation(forceBuildDir: true);

    TestTargetFlags targetFlags = new TestTargetFlags(
        forceLateLoweringsForTesting:
            forceLateLoweringForTesting ? LateLowering.all : null,
        trackWidgetCreation: trackWidgetCreation);
    Target target = new VmTarget(targetFlags);
    if (targetName != null) {
      if (targetName == "None") {
        target = new NoneTarget(targetFlags);
      } else if (targetName == "DDC") {
        target = new DevCompilerTarget(targetFlags);
      } else if (targetName == "dart2js") {
        target = new Dart2jsTarget("dart2js", targetFlags);
      } else if (targetName == "VM") {
        // default.
      } else {
        throw "Unknown target name '$targetName'";
      }
    }
    Target originalTarget = target;
    target = new TestTargetWrapper(target, targetFlags);

    String sdkSummary = computePlatformDillName(
        target,
        nnbdMode,
        () => throw new UnsupportedError(
            "No platform dill for target '${targetName}' with $nnbdMode."))!;

    final Uri base = Uri.parse("org-dartlang-test:///");
    final Uri sdkSummaryUri = base.resolve(sdkSummary);
    final Uri initializeFrom = base.resolve("initializeFrom.dill");
    Uri platformUri = sdkRoot.resolve(sdkSummary);
    final List<int> sdkSummaryData =
        await new File.fromUri(platformUri).readAsBytes();

    List<int>? newestWholeComponentData;
    MemoryFileSystem? fs;
    Map<String, String?>? sourceFiles;
    CompilerOptions? options;
    TestIncrementalCompiler? compiler;
    IncrementalSerializer? incrementalSerializer;

    Map<String, List<int>>? moduleData;
    Map<String, Component>? moduleComponents;

    if (modules != null) {
      moduleData = await createModules(
          modules, sdkSummaryData, target, originalTarget, sdkSummary,
          trackNeededDillLibraries: false);
      sdk = newestWholeComponent = new Component();
      new BinaryBuilder(sdkSummaryData,
              filename: null, disableLazyReading: false)
          .readComponent(newestWholeComponent!);
    }

    int worldNum = 0;
    // TODO: When needed, we can do this for warnings too.
    List<Set<String>> worldErrors = [];
    for (YamlMap world in worlds) {
      worldNum++;
      print("----------------");
      print("World #$worldNum");
      print("----------------");
      List<Component>? modulesToUse;
      if (world["modules"] != null) {
        moduleComponents ??= new Map<String, Component>();

        sdk!.adoptChildren();
        for (Component c in moduleComponents.values) {
          c.adoptChildren();
        }

        modulesToUse = <Component>[];
        for (String moduleName in world["modules"]) {
          Component? moduleComponent = moduleComponents[moduleName];
          if (moduleComponent != null) {
            modulesToUse.add(moduleComponent);
          }
        }
        for (String moduleName in world["modules"]) {
          Component? moduleComponent = moduleComponents[moduleName];
          if (moduleComponent == null) {
            moduleComponent = new Component(nameRoot: sdk!.root);
            new BinaryBuilder(moduleData![moduleName]!,
                    filename: null,
                    disableLazyReading: false,
                    alwaysCreateNewNamedNodes: true)
                .readComponent(moduleComponent);
            moduleComponents[moduleName] = moduleComponent;
            modulesToUse.add(moduleComponent);
          }
        }
      }

      bool brandNewWorld = true;
      if (world["worldType"] == "updated") {
        brandNewWorld = false;
      }
      bool noFullComponent = false;
      if (world["noFullComponent"] == true) {
        noFullComponent = true;
      }

      if (brandNewWorld) {
        fs = new TestMemoryFileSystem(base);
      }
      fs!.entityForUri(sdkSummaryUri).writeAsBytesSync(sdkSummaryData);
      bool expectInitializeFromDill = false;
      if (newestWholeComponentData != null &&
          newestWholeComponentData.isNotEmpty) {
        fs
            .entityForUri(initializeFrom)
            .writeAsBytesSync(newestWholeComponentData);
        expectInitializeFromDill = true;
      }
      if (world["expectInitializeFromDill"] != null) {
        expectInitializeFromDill = world["expectInitializeFromDill"];
      }
      if (brandNewWorld) {
        sourceFiles = new Map<String, String?>.from(world["sources"]);
      } else {
        sourceFiles!.addAll(new Map<String, String?>.from(
            world["sources"] ?? <String, String?>{}));
      }
      Uri? packagesUri;
      for (String filename in sourceFiles.keys) {
        String data = sourceFiles[filename] ?? "";
        Uri uri = base.resolve(filename);
        if (filename == ".dart_tool/package_config.json") {
          packagesUri = uri;
        }
        if (world["enableStringReplacement"] == true) {
          data = doStringReplacements(data);
        }
        fs.entityForUri(uri).writeAsStringSync(data);
      }
      if (world["packageConfigFile"] != null) {
        packagesUri = base.resolve(world["packageConfigFile"]);
      }

      if (brandNewWorld) {
        options = getOptions(target: target, sdkSummary: sdkSummary);
        options.nnbdMode = nnbdMode;
        options.fileSystem = fs;
        options.sdkRoot = null;
        options.sdkSummary = sdkSummaryUri;
        if (world["badSdk"] == true) {
          options.sdkSummary = sdkSummaryUri.resolve("nonexisting.dill");
        }
        options.omitPlatform = omitPlatform != false;
        if (world["experiments"] != null) {
          Map<String, bool> flagsFromOptions =
              parseExperimentalArguments([world["experiments"]]);
          // Ensure that we run with non-nullable turned off even when the
          // flag is on by default.
          Map<ExperimentalFlag, bool> explicitExperimentalFlags =
              parseExperimentalFlags(flagsFromOptions,
                  onError: (e) =>
                      throw "Error on parsing experiments flags: $e");
          options.explicitExperimentalFlags = explicitExperimentalFlags;
        } else {
          options.explicitExperimentalFlags = {};
        }
        // A separate "world" can also change nnbd mode ---
        // notice that the platform is not updated though!
        if (world["nnbdMode"] != null) {
          String nnbdMode = world["nnbdMode"];
          switch (nnbdMode) {
            case "strong":
              options.nnbdMode = NnbdMode.Strong;
              break;
            default:
              throw "Not supported nnbd mode: $nnbdMode";
          }
        }
      }
      if (packagesUri != null) {
        options!.packagesFileUri = packagesUri;
      }
      bool gotError = false;
      final Set<String> formattedErrors = Set<String>();
      bool gotWarning = false;
      final Set<String> formattedWarnings = Set<String>();
      final Set<String> seenDiagnosticCodes = Set<String>();

      options!.onDiagnostic = (DiagnosticMessage message) {
        String? code = getMessageCodeObject(message)?.name;
        if (code != null) seenDiagnosticCodes.add(code);

        String stringId = message.ansiFormatted.join("\n");
        if (message is FormattedMessage) {
          stringId = message.toJsonString();
        } else if (message is DiagnosticMessageFromJson) {
          stringId = message.toJsonString();
        }
        if (message.severity == Severity.error) {
          gotError = true;
          if (!formattedErrors.add(stringId)) {
            Expect.fail("Got the same message twice: ${stringId}");
          }
        } else if (message.severity == Severity.warning) {
          gotWarning = true;
          if (!formattedWarnings.add(stringId)) {
            Expect.fail("Got the same message twice: ${stringId}");
          }
        }
      };

      List<Uri> entries;
      if (world["entry"] is String) {
        entries = [base.resolve(world["entry"])];
      } else {
        entries = <Uri>[];
        List<dynamic> entryList = world["entry"];
        for (String entry in entryList) {
          entries.add(base.resolve(entry));
        }
      }
      bool outlineOnly = world["outlineOnly"] == true;
      bool skipOutlineBodyCheck = world["skipOutlineBodyCheck"] == true;
      if (brandNewWorld) {
        if (incrementalSerialization == true) {
          incrementalSerializer = new IncrementalSerializer();
        }
        if (world["fromComponent"] == true) {
          compiler = new TestIncrementalCompiler.fromComponent(
              options,
              entries.first,
              (modulesToUse != null) ? sdk : newestWholeComponent,
              outlineOnly,
              incrementalSerializer);
        } else {
          compiler = new TestIncrementalCompiler(options, entries.first,
              initializeFrom, outlineOnly, incrementalSerializer);

          if (modulesToUse != null) {
            throw "You probably shouldn't do this! "
                "Any modules will have another sdk loaded!";
          }
        }
      }

      List<Uri> invalidated = <Uri>[];
      if (world["invalidate"] != null) {
        for (String filename in world["invalidate"]) {
          Uri uri = base.resolve(filename);
          invalidated.add(uri);
          compiler!.invalidate(uri);
        }
      }

      if (modulesToUse != null) {
        compiler!.setModulesToLoadOnNextComputeDelta(modulesToUse);
        compiler.invalidateAllSources();
      }

      Stopwatch stopwatch = new Stopwatch()..start();
      IncrementalCompilerResult? compilerResult = await compiler!.computeDelta(
          entryPoints: entries,
          fullComponent:
              brandNewWorld ? false : (noFullComponent ? false : true),
          trackNeededDillLibraries: modulesToUse != null,
          simulateTransformer: world["simulateTransformer"]);
      component = compilerResult.component;
      // compilerResult is null'ed out at the end to avoid any
      // "artificial memory leak" on that account.
      if (outlineOnly && !skipOutlineBodyCheck) {
        for (Library lib in component!.libraries) {
          for (Class c in lib.classes) {
            for (Procedure p in c.procedures) {
              if (p.function.body != null &&
                  p.function.body is! EmptyStatement) {
                throw "Got body (${p.function.body.runtimeType})";
              }
            }
          }
          for (Procedure p in lib.procedures) {
            if (p.function.body != null && p.function.body is! EmptyStatement) {
              throw "Got body (${p.function.body.runtimeType})";
            }
          }
        }
      }
      Result<TestData>? result = performErrorAndWarningCheck(world, data,
          gotError, formattedErrors, gotWarning, formattedWarnings);
      if (result != null) return result;
      if (world["expectInitializationError"] != null) {
        Set<String> seenInitializationError = seenDiagnosticCodes.intersection({
          "InitializeFromDillNotSelfContainedNoDump",
          "InitializeFromDillNotSelfContained",
          "InitializeFromDillUnknownProblem",
          "InitializeFromDillUnknownProblemNoDump",
        });
        if (world["expectInitializationError"] == true) {
          if (seenInitializationError.isEmpty) {
            return new Result<TestData>(data, MissingInitializationError,
                "Expected to see an initialization error but didn't.");
          }
        } else if (world["expectInitializationError"] == false) {
          if (seenInitializationError.isNotEmpty) {
            return new Result<TestData>(
                data,
                UnexpectedInitializationError,
                "Expected not to see an initialization error but did: "
                "$seenInitializationError.");
          }
        } else {
          throw "Unsupported value for 'expectInitializationError': "
              "${world["expectInitializationError"]}";
        }
      }
      util.throwOnEmptyMixinBodies(component!);
      await util.throwOnInsufficientUriToSource(component!,
          fileSystem: gotError ? null : fs);
      print("Compile took ${stopwatch.elapsedMilliseconds} ms");

      Result? contentResult = checkExpectedContent(world, component!);
      if (contentResult != null) return contentResult.copyWithOutput(data);
      result = checkNeededDillLibraries(
          world, data, compilerResult.neededDillLibraries, base);
      if (result != null) return result;

      Result? nnbdCheck = checkNNBDSettings(component!);
      if (nnbdCheck != null) return nnbdCheck.copyWithOutput(data);

      if (!noFullComponent) {
        Set<Library> allLibraries = new Set<Library>();
        for (Library lib in component!.libraries) {
          computeAllReachableLibrariesFor(lib, allLibraries);
        }
        if (allLibraries.length != component!.libraries.length) {
          return new Result<TestData>(
              data,
              ReachableLibrariesError,
              "Expected for the reachable stuff to be equal to "
              "${component!.libraries} but it was $allLibraries");
        }
        Set<Library> tooMany = allLibraries.toSet()
          ..removeAll(component!.libraries);
        if (tooMany.isNotEmpty) {
          return new Result<TestData>(
              data,
              ReachableLibrariesError,
              "Expected for the reachable stuff to be equal to "
              "${component!.libraries} but these were there too: $tooMany "
              "(and others were missing)");
        }
      }

      util.postProcessComponent(component!);
      String actualSerialized = componentToStringSdkFiltered(component!);
      print("*****\n\ncomponent:\n"
          "${actualSerialized}\n\n\n");
      result = checkExpectFile(data, worldNum, "", context, actualSerialized);
      if (result != null) return result;

      if (world["compareToPrevious"] == true && newestWholeComponent != null) {
        EquivalenceResult result = checkEquivalence(
            newestWholeComponent!, component!,
            strategy: const Strategy());
        if (!result.isEquivalent) {
          return new Result<TestData>(
              data, EquivalenceError, result.toString());
        }
      }

      newestWholeComponentData = util.postProcess(component!);
      newestWholeComponent = component;

      if (world["uriToSourcesDoesntInclude"] != null) {
        for (String filename in world["uriToSourcesDoesntInclude"]) {
          Uri uri = base.resolve(filename);
          if (component!.uriToSource[uri] != null) {
            return new Result<TestData>(
                data,
                UriToSourceError,
                "Expected no uriToSource for $uri but found "
                "${component!.uriToSource[uri]}");
          }
        }
      }
      if (world["uriToSourcesOnlyIncludes"] != null) {
        Set<Uri> allowed = {};
        for (String filename in world["uriToSourcesOnlyIncludes"]) {
          Uri uri = base.resolve(filename);
          allowed.add(uri);
        }
        for (Uri uri in component!.uriToSource.keys) {
          // null is always there, so allow it implicitly.
          // Dart scheme uris too.
          // ignore: unnecessary_null_comparison
          if (uri == null || uri.isScheme("org-dartlang-sdk")) continue;
          if (!allowed.contains(uri)) {
            return new Result<TestData>(
                data,
                UriToSourceError,
                "Expected no uriToSource for $uri but found "
                "${component!.uriToSource[uri]}");
          }
        }
      }

      if (world["skipClassHierarchyTest"] != true) {
        result = checkClassHierarchy(compilerResult, data, worldNum, context);
        if (result != null) return result;
      }

      int nonSyntheticLibraries = countNonSyntheticLibraries(component!);
      int nonSyntheticPlatformLibraries =
          countNonSyntheticPlatformLibraries(component!);
      int syntheticLibraries = countSyntheticLibraries(component!);
      if (world["expectsPlatform"] == true) {
        if (nonSyntheticPlatformLibraries < 5) {
          return new Result<TestData>(
              data,
              MissingPlatformLibraries,
              "Expected to have at least 5 platform libraries "
              "(actually, the entire sdk), "
              "but got $nonSyntheticPlatformLibraries.");
        }
      } else {
        if (nonSyntheticPlatformLibraries != 0) {
          return new Result<TestData>(
              data,
              UnexpectedPlatformLibraries,
              "Expected to have 0 platform libraries "
              "but got $nonSyntheticPlatformLibraries.");
        }
      }
      if (world["expectedLibraryCount"] != null) {
        if (nonSyntheticLibraries - nonSyntheticPlatformLibraries !=
            world["expectedLibraryCount"]) {
          return new Result<TestData>(
              data,
              LibraryCountMismatch,
              "Expected ${world["expectedLibraryCount"]} non-synthetic "
              "libraries, got "
              "${nonSyntheticLibraries - nonSyntheticPlatformLibraries} "
              "(not counting platform libraries)");
        }
      }
      if (world["expectedSyntheticLibraryCount"] != null) {
        if (syntheticLibraries != world["expectedSyntheticLibraryCount"]) {
          return new Result<TestData>(
              data,
              LibraryCountMismatch,
              "Expected ${world["expectedSyntheticLibraryCount"]} synthetic "
              "libraries, got ${syntheticLibraries}");
        }
      }

      if (world["expectsRebuildBodiesOnly"] != null) {
        bool didRebuildBodiesOnly =
            compiler.recorderForTesting.rebuildBodiesCount! > 0;
        if (world["expectsRebuildBodiesOnly"] != didRebuildBodiesOnly) {
          return new Result<TestData>(
              data,
              UnexpectedRebuildBodiesOnly,
              "Expected didRebuildBodiesOnly="
              "${world["expectsRebuildBodiesOnly"]}, "
              "didRebuildBodiesOnly=${didRebuildBodiesOnly}.");
        }
      }

      if (!noFullComponent) {
        if (world["checkEntries"] != false) {
          List<Library> entryLib = component!.libraries
              .where((Library lib) =>
                  entries.contains(lib.importUri) ||
                  entries.contains(lib.fileUri))
              .toList();
          if (entryLib.length != entries.length) {
            return new Result<TestData>(
                data,
                UnexpectedEntryToLibraryCount,
                "Expected the entries to become libraries. "
                "Got ${entryLib.length} libraries for the expected "
                "${entries.length} entries.");
          }
        }
      }
      if (compiler.initializedFromDillForTesting != expectInitializeFromDill) {
        return new Result<TestData>(
            data,
            InitializedFromDillMismatch,
            "Expected that initializedFromDill would be "
            "$expectInitializeFromDill but was "
            "${compiler.initializedFromDillForTesting}");
      }

      if (incrementalSerialization == true &&
          compiler.initializedFromDillForTesting) {
        Expect.isTrue(compiler.initializedIncrementalSerializerForTesting);
      } else {
        Expect.isFalse(compiler.initializedIncrementalSerializerForTesting);
      }

      if (world["checkInvalidatedFiles"] != false) {
        Set<Uri>? filteredInvalidated =
            compiler.getFilteredInvalidatedImportUrisForTesting(invalidated);
        if (world["invalidate"] != null) {
          Expect.equals(
              world["invalidate"].length, filteredInvalidated?.length ?? 0);
          List? expectedInvalidatedUri = world["expectedInvalidatedUri"];
          if (expectedInvalidatedUri != null) {
            Expect.setEquals(expectedInvalidatedUri.map((s) => base.resolve(s)),
                filteredInvalidated!);
          }
        } else {
          Expect.isNull(filteredInvalidated);
          Expect.isNull(world["expectedInvalidatedUri"]);
        }
      }
      Result<List<int>?> serializationResult = checkIncrementalSerialization(
          incrementalSerialization, component!, incrementalSerializer, world);
      if (!serializationResult.isPass) {
        return serializationResult.copyWithOutput(data);
      }
      List<int>? incrementalSerializationBytes = serializationResult.output;

      worldErrors.add(formattedErrors.toSet());
      assert(worldErrors.length == worldNum);
      if (world["expectSameErrorsAsWorld"] != null) {
        int expectSameErrorsAsWorld = world["expectSameErrorsAsWorld"];
        checkErrorsAndWarnings(
          worldErrors[expectSameErrorsAsWorld - 1],
          formattedErrors,
          {},
          {},
        );
      }

      Set<String> prevFormattedErrors = formattedErrors.toSet();
      Set<String> prevFormattedWarnings = formattedWarnings.toSet();

      void clearPrevErrorsEtc() {
        gotError = false;
        formattedErrors.clear();
        gotWarning = false;
        formattedWarnings.clear();
      }

      if (!noFullComponent) {
        clearPrevErrorsEtc();
        IncrementalCompilerResult? compilerResult2 =
            await compiler.computeDelta(
                entryPoints: entries,
                fullComponent: true,
                simulateTransformer: world["simulateTransformer"]);
        component2 = compilerResult2.component;
        compilerResult2 = null;
        Result<TestData>? result = performErrorAndWarningCheck(world, data,
            gotError, formattedErrors, gotWarning, formattedWarnings);
        if (result != null) return result;
        List<int> thisWholeComponent = util.postProcess(component2!);
        print("*****\n\ncomponent2:\n"
            "${componentToStringSdkFiltered(component2!)}\n\n\n");
        checkIsEqual(newestWholeComponentData, thisWholeComponent);
        checkErrorsAndWarnings(prevFormattedErrors, formattedErrors,
            prevFormattedWarnings, formattedWarnings);
        newestWholeComponent = component2;

        Result<List<int>?> serializationResult = checkIncrementalSerialization(
            incrementalSerialization,
            component2!,
            incrementalSerializer,
            world);
        if (!serializationResult.isPass) {
          return serializationResult.copyWithOutput(data);
        }
        List<int>? incrementalSerializationBytes2 = serializationResult.output;

        if ((incrementalSerializationBytes == null &&
                incrementalSerializationBytes2 != null) ||
            (incrementalSerializationBytes != null &&
                incrementalSerializationBytes2 == null)) {
          return new Result<TestData>(
              data,
              IncrementalSerializationError,
              "Incremental serialization gave results in one instance, "
              "but not another.");
        }

        if (incrementalSerializationBytes != null) {
          checkIsEqual(
              incrementalSerializationBytes, incrementalSerializationBytes2!);
        }
      }

      if (world["expressionCompilation"] != null) {
        List compilations;
        if (world["expressionCompilation"] is List) {
          compilations = world["expressionCompilation"];
        } else {
          compilations = [world["expressionCompilation"]];
        }
        int expressionCompilationNum = 0;
        for (Map compilation in compilations) {
          expressionCompilationNum++;
          clearPrevErrorsEtc();
          bool expectErrors = compilation["errors"] ?? false;
          bool expectWarnings = compilation["warnings"] ?? false;
          Uri uri = base.resolve(compilation["uri"]);
          String expression = compilation["expression"];
          Procedure procedure = (await compiler.compileExpression(
              expression, {}, [], "debugExpr", uri))!;
          if (gotError && !expectErrors) {
            return new Result<TestData>(data, UnexpectedErrors,
                "Got error(s) on expression compilation: ${formattedErrors}.");
          } else if (!gotError && expectErrors) {
            return new Result<TestData>(
                data, MissingErrors, "Didn't get any errors.");
          }
          if (gotWarning && !expectWarnings) {
            return new Result<TestData>(
                data,
                UnexpectedWarnings,
                "Got warning(s) on expression compilation: "
                "${formattedWarnings}.");
          } else if (!gotWarning && expectWarnings) {
            return new Result<TestData>(
                data, MissingWarnings, "Didn't get any warnings.");
          }
          Result<TestData>? result = checkExpectFile(
              data,
              worldNum,
              ".expression.$expressionCompilationNum",
              context,
              nodeToString(procedure));
          if (result != null) return result;
        }
      }

      if (!noFullComponent &&
          (incrementalSerialization == true ||
              world["compareWithFromScratch"] == true)) {
        // Do compile from scratch and compare.
        clearPrevErrorsEtc();
        TestIncrementalCompiler? compilerFromScratch;

        IncrementalSerializer? incrementalSerializer2;
        if (incrementalSerialization == true) {
          incrementalSerializer2 = new IncrementalSerializer();
        }

        if (world["fromComponent"] == true || modulesToUse != null) {
          compilerFromScratch = new TestIncrementalCompiler.fromComponent(
              options, entries.first, sdk, outlineOnly, incrementalSerializer2);
        } else {
          compilerFromScratch = new TestIncrementalCompiler(options,
              entries.first, null, outlineOnly, incrementalSerializer2);
        }

        if (modulesToUse != null) {
          compilerFromScratch.setModulesToLoadOnNextComputeDelta(modulesToUse);
          compilerFromScratch.invalidateAllSources();
        }

        Stopwatch stopwatch = new Stopwatch()..start();
        IncrementalCompilerResult? compilerResult3 =
            await compilerFromScratch.computeDelta(
                entryPoints: entries,
                trackNeededDillLibraries: modulesToUse != null,
                simulateTransformer: world["simulateTransformer"]);
        component3 = compilerResult3.component;
        compilerResult3 = null;
        compilerFromScratch = null;
        Result<TestData>? result = performErrorAndWarningCheck(world, data,
            gotError, formattedErrors, gotWarning, formattedWarnings);
        if (result != null) return result;
        util.throwOnEmptyMixinBodies(component3!);
        await util.throwOnInsufficientUriToSource(component3!);
        print("Compile took ${stopwatch.elapsedMilliseconds} ms");

        List<int> thisWholeComponent = util.postProcess(component3!);
        print("*****\n\ncomponent3:\n"
            "${componentToStringSdkFiltered(component3!)}\n\n\n");
        if (world["compareWithFromScratch"] == true) {
          checkIsEqual(newestWholeComponentData, thisWholeComponent);
        }
        checkErrorsAndWarnings(prevFormattedErrors, formattedErrors,
            prevFormattedWarnings, formattedWarnings);

        Result<List<int>?> serializationResult = checkIncrementalSerialization(
            incrementalSerialization,
            component3!,
            incrementalSerializer2,
            world);
        if (!serializationResult.isPass) {
          return serializationResult.copyWithOutput(data);
        }
        List<int>? incrementalSerializationBytes3 = serializationResult.output;

        if ((incrementalSerializationBytes == null &&
                incrementalSerializationBytes3 != null) ||
            (incrementalSerializationBytes != null &&
                incrementalSerializationBytes3 == null)) {
          return new Result<TestData>(
              data,
              IncrementalSerializationError,
              "Incremental serialization gave results in one instance, "
              "but not another.");
        }

        if (incrementalSerializationBytes != null) {
          if (world["brandNewIncrementalSerializationAllowDifferent"] == true) {
            // Don't check for equality when we allow it to be different
            // (e.g. when the old one contains more, and the new one doesn't).
          } else {
            checkIsEqual(
                incrementalSerializationBytes, incrementalSerializationBytes3!);
          }
          newestWholeComponentData = incrementalSerializationBytes;
        }
      }

      component = null;
      compilerResult = null;
      component2 = null;
      component3 = null;
      // Dummy tree nodes can (currently) leak though the parent pointer.
      // To avoid that (here) (for leak testing) we'll null them out.
      for (TreeNode treeNode in dummyTreeNodes) {
        treeNode.parent = null;
      }

      if (context.breakBetween) {
        debugger();
        print("Continuing after debug break");
      }
    }
    return new Result<TestData>.pass(data);
  }
}

class Strategy extends EquivalenceStrategy {
  const Strategy();

  @override
  bool checkComponent_libraries(
      EquivalenceVisitor visitor, Component node, Component other) {
    return visitor.checkSets(node.libraries.toSet(), other.libraries.toSet(),
        visitor.matchNamedNodes, visitor.checkNodes, 'libraries');
  }

  @override
  bool checkClass_procedures(
      EquivalenceVisitor visitor, Class node, Class other) {
    // Check procedures as a set instead of a list to allow for reordering.
    return visitor.checkSets(node.procedures.toSet(), other.procedures.toSet(),
        visitor.matchNamedNodes, visitor.checkNodes, 'procedures');
  }

  @override
  bool checkVariableDeclaration_binaryOffsetNoTag(EquivalenceVisitor visitor,
      VariableDeclaration node, VariableDeclaration other) {
    return true;
  }
}

Result? checkNNBDSettings(Component component) {
  NonNullableByDefaultCompiledMode mode = component.mode;
  if (mode == NonNullableByDefaultCompiledMode.Invalid) return null;
  for (Library lib in component.libraries) {
    if (mode == lib.nonNullableByDefaultCompiledMode) continue;

    if (mode == NonNullableByDefaultCompiledMode.Agnostic) {
      // Component says agnostic but the library isn't => Error!
      return new Result(
          null,
          NNBDModeMismatch,
          "Component mode was agnostic but ${lib.importUri} had mode "
          "${lib.nonNullableByDefaultCompiledMode}.");
    }

    // Agnostic can be mixed with everything.
    if (lib.nonNullableByDefaultCompiledMode ==
        NonNullableByDefaultCompiledMode.Agnostic) continue;

    if (mode == NonNullableByDefaultCompiledMode.Strong ||
        lib.nonNullableByDefaultCompiledMode ==
            NonNullableByDefaultCompiledMode.Strong) {
      // Non agnostic and one (but not both) are strong => error.
      return new Result(
          null,
          NNBDModeMismatch,
          "Component mode was $mode but ${lib.importUri} had mode "
          "${lib.nonNullableByDefaultCompiledMode}.");
    }
  }
  return null;
}

Result<TestData>? checkExpectFile(TestData data, int worldNum,
    String extraUriString, Context context, String actualSerialized) {
  Uri uri = data.loadedFrom.resolve(data.loadedFrom.pathSegments.last +
      ".world.$worldNum${extraUriString}.expect");
  String? expected;
  File file = new File.fromUri(uri);
  if (file.existsSync()) {
    expected = file.readAsStringSync();
  }
  if (expected != actualSerialized) {
    if (context.updateExpectations) {
      file.writeAsStringSync(actualSerialized);
    } else {
      String extra = "";
      if (expected == null) extra = "Expect file did not exist.\n";
      return new Result<TestData>(
          data,
          expected == null ? ExpectationFileMissing : ExpectationFileMismatch,
          "${extra}Unexpected serialized representation. "
          "Fix or update $uri to contain the below:\n\n"
          "$actualSerialized",
          autoFixCommand: "updateExpectations=true",
          canBeFixWithUpdateExpectations: true);
    }
  }
  return null;
}

/// Check that the class hierarchy is up-to-date with reality.
///
/// This has the option to do expect files, but it's disabled by default
/// while we're trying to figure out if it's useful or not.
Result<TestData>? checkClassHierarchy(IncrementalCompilerResult compilerResult,
    TestData data, int worldNum, Context context,
    {bool checkExpectFile: false}) {
  ClassHierarchy? classHierarchy = compilerResult.classHierarchy;
  if (classHierarchy is! ClosedWorldClassHierarchy) {
    return new Result<TestData>(
        data,
        ClassHierarchyError,
        "Expected the class hierarchy to be ClosedWorldClassHierarchy "
        "but it wasn't. It was ${classHierarchy.runtimeType}");
  }
  List<ForTestingClassInfo> classHierarchyData =
      classHierarchy.getTestingClassInfo();
  Map<Class, ForTestingClassInfo> classHierarchyMap =
      new Map<Class, ForTestingClassInfo>();
  for (ForTestingClassInfo info in classHierarchyData) {
    if (classHierarchyMap[info.classNode] != null) {
      return new Result<TestData>(
          data, ClassHierarchyError, "Two entries for ${info.classNode}");
    }
    classHierarchyMap[info.classNode] = info;
  }

  Component component = compilerResult.component;
  StringBuffer sb = new StringBuffer();
  for (Library library in component.libraries) {
    if (library.importUri.isScheme("dart")) continue;
    sb.writeln("Library ${library.importUri}");
    for (Class c in library.classes) {
      sb.writeln("  - Class ${c.name}");

      Set<Class> checkedSupertypes = <Class>{};
      Result<TestData>? checkSupertype(Supertype? supertype) {
        if (supertype == null) return null;
        Class superclass = supertype.classNode;
        if (checkedSupertypes.add(superclass)) {
          Supertype? asSuperClass =
              classHierarchy.getClassAsInstanceOf(c, superclass);
          if (asSuperClass == null) {
            return new Result<TestData>(data, ClassHierarchyError,
                "${superclass} not found as a superclass of $c");
          }
          Result<TestData>? result = checkSupertype(superclass.supertype);
          if (result != null) return result;
          result = checkSupertype(superclass.mixedInType);
          if (result != null) return result;
          for (Supertype interface in superclass.implementedTypes) {
            result = checkSupertype(interface);
            if (result != null) return result;
          }
        }
        return null;
      }

      Result<TestData>? result = checkSupertype(c.asThisSupertype);
      if (result != null) return result;

      ForTestingClassInfo? info = classHierarchyMap[c];
      if (info == null) {
        return new Result<TestData>(data, ClassHierarchyError,
            "Didn't find any class hierarchy info for $c");
      }

      if (info.lazyDeclaredGettersAndCalls != null) {
        sb.writeln("    - lazyDeclaredGettersAndCalls:");
        for (Member member in info.lazyDeclaredGettersAndCalls!) {
          sb.writeln("      - ${member.name.text}");
        }

        // Expect these to be the same as in the class.
        Set<Member> members = info.lazyDeclaredGettersAndCalls!.toSet();
        for (Field f in c.fields) {
          if (f.isStatic) continue;
          if (!members.remove(f)) {
            return new Result<TestData>(
                data,
                ClassHierarchyError,
                "Didn't find ${f.name.text} in lazyDeclaredGettersAndCalls "
                "for ${c.name} in ${library.importUri}");
          }
        }
        for (Procedure p in c.procedures) {
          if (p.isStatic) continue;
          if (p.isSetter) continue;
          if (!members.remove(p)) {
            return new Result<TestData>(
                data,
                ClassHierarchyError,
                "Didn't find ${p.name.text} in lazyDeclaredGettersAndCalls "
                "for ${c.name} in ${library.importUri}");
          }
        }
        if (members.isNotEmpty) {
          return new Result<TestData>(
              data,
              ClassHierarchyError,
              "Still have ${members.map((m) => m.name.text)} left "
              "for ${c.name} in ${library.importUri}");
        }
      }
      if (info.lazyDeclaredSetters != null) {
        sb.writeln("    - lazyDeclaredSetters:");
        for (Member member in info.lazyDeclaredSetters!) {
          sb.writeln("      - ${member.name.text}");
        }

        // Expect these to be the same as in the class.
        Set<Member> members = info.lazyDeclaredSetters!.toSet();
        for (Field f in c.fields) {
          if (f.isStatic) continue;
          if (!f.hasSetter) continue;
          if (!members.remove(f)) {
            return new Result<TestData>(data, ClassHierarchyError,
                "Didn't find $f in lazyDeclaredSetters for $c");
          }
        }
        for (Procedure p in c.procedures) {
          if (p.isStatic) continue;
          if (!p.isSetter) continue;
          if (!members.remove(p)) {
            return new Result<TestData>(data, ClassHierarchyError,
                "Didn't find $p in lazyDeclaredSetters for $c");
          }
        }
        if (members.isNotEmpty) {
          return new Result<TestData>(
              data,
              ClassHierarchyError,
              "Still have ${members.map((m) => m.name.text)} left "
              "for ${c.name} in ${library.importUri}");
        }
      }
      if (info.lazyImplementedGettersAndCalls != null) {
        sb.writeln("    - lazyImplementedGettersAndCalls:");
        for (Member member in info.lazyImplementedGettersAndCalls!) {
          sb.writeln("      - ${member.name.text}");
        }
      }
      if (info.lazyImplementedSetters != null) {
        sb.writeln("    - lazyImplementedSetters:");
        for (Member member in info.lazyImplementedSetters!) {
          sb.writeln("      - ${member.name.text}");
        }
      }
      if (info.lazyInterfaceGettersAndCalls != null) {
        sb.writeln("    - lazyInterfaceGettersAndCalls:");
        for (Member member in info.lazyInterfaceGettersAndCalls!) {
          sb.writeln("      - ${member.name.text}");
        }
      }
      if (info.lazyInterfaceSetters != null) {
        sb.writeln("    - lazyInterfaceSetters:");
        for (Member member in info.lazyInterfaceSetters!) {
          sb.writeln("      - ${member.name.text}");
        }
      }
    }
  }
  if (checkExpectFile) {
    String actualClassHierarchy = sb.toString();
    Uri uri = data.loadedFrom.resolve(data.loadedFrom.pathSegments.last +
        ".world.$worldNum.class_hierarchy.expect");
    String? expected;
    File file = new File.fromUri(uri);
    if (file.existsSync()) {
      expected = file.readAsStringSync();
    }
    if (expected != actualClassHierarchy) {
      if (context.updateExpectations) {
        file.writeAsStringSync(actualClassHierarchy);
      } else {
        String extra = "";
        if (expected == null) extra = "Expect file did not exist.\n";
        return new Result<TestData>(
            data,
            ClassHierarchyError,
            "${extra}Unexpected serialized representation. "
            "Fix or update $uri to contain the below:\n\n"
            "$actualClassHierarchy");
      }
    }
  }
  return null;
}

void checkErrorsAndWarnings(
    Set<String> prevFormattedErrors,
    Set<String> formattedErrors,
    Set<String> prevFormattedWarnings,
    Set<String> formattedWarnings) {
  if (prevFormattedErrors.length != formattedErrors.length) {
    Expect.fail("Previously had ${prevFormattedErrors.length} errors, "
        "now had ${formattedErrors.length}.\n\n"
        "Before:\n"
        "${prevFormattedErrors.join("\n")}"
        "\n\n"
        "Now:\n"
        "${formattedErrors.join("\n")}");
  }
  if ((prevFormattedErrors.toSet()..removeAll(formattedErrors)).isNotEmpty) {
    Expect.fail("Previously got error messages $prevFormattedErrors, "
        "now had ${formattedErrors}.");
  }
  if (prevFormattedWarnings.length != formattedWarnings.length) {
    Expect.fail("Previously had ${prevFormattedWarnings.length} errors, "
        "now had ${formattedWarnings.length}.");
  }
  if ((prevFormattedWarnings.toSet()..removeAll(formattedWarnings))
      .isNotEmpty) {
    Expect.fail("Previously got error messages $prevFormattedWarnings, "
        "now had ${formattedWarnings}.");
  }
}

Result<List<int>?> checkIncrementalSerialization(
    bool? incrementalSerialization,
    Component component,
    IncrementalSerializer? incrementalSerializer,
    YamlMap world) {
  if (incrementalSerialization == true) {
    Component c = new Component(nameRoot: component.root)
      ..setMainMethodAndMode(null, false, component.mode);
    c.libraries.addAll(component.libraries);
    c.uriToSource.addAll(component.uriToSource);
    Map<String, Set<String>> originalContent = buildMapOfContent(c);
    ByteSink sink = new ByteSink();
    int librariesBefore = c.libraries.length;
    incrementalSerializer!.writePackagesToSinkAndTrimComponent(c, sink);
    int librariesAfter = c.libraries.length;
    if (librariesAfter > librariesBefore) {
      return new Result<List<int>>(null, IncrementalSerializationError,
          "Incremental serialization added libraries!");
    }
    if (librariesBefore == librariesAfter &&
        world["incrementalSerializationDoesWork"] == true) {
      return new Result<List<int>>(null, IncrementalSerializationError,
          "Incremental serialization didn't remove any libraries!");
    }
    if (librariesAfter < librariesBefore && sink.builder.isEmpty) {
      return new Result<List<int>>(
          null,
          IncrementalSerializationError,
          "Incremental serialization didn't output any bytes, "
          "but did remove libraries");
    } else if (librariesAfter == librariesBefore && !sink.builder.isEmpty) {
      return new Result<List<int>>(
          null,
          IncrementalSerializationError,
          "Incremental serialization did output bytes, "
          "but didn't remove libraries");
    }
    if (librariesAfter < librariesBefore) {
      // If we actually did incrementally serialize anything, check the output!
      BinaryPrinter printer = new BinaryPrinter(sink);
      printer.writeComponentFile(c);
      List<int> bytes = sink.builder.takeBytes();

      // Load the bytes back in.
      Component loadedComponent = new Component();
      new BinaryBuilder(bytes, filename: null).readComponent(loadedComponent);

      // Check that it doesn't contain anything we said it shouldn't.
      if (world["serializationShouldNotInclude"] is List) {
        List serializationShouldNotInclude =
            world["serializationShouldNotInclude"];
        Set<Uri> includedImportUris =
            loadedComponent.libraries.map((l) => l.importUri).toSet();
        for (String uriString in serializationShouldNotInclude) {
          Uri uri = Uri.parse(uriString);
          if (includedImportUris.contains(uri)) {
            return new Result<List<int>>(
                null,
                IncrementalSerializationError,
                "Incremental serialization shouldn't include "
                "$uriString but did.");
          }
        }
      }

      // Check that it contains at least what we want.
      Map<String, Set<String>> afterContent =
          buildMapOfContent(loadedComponent);
      // Remove any keys in afterContent not in the original as the written
      // one is allowed to contain *more*.
      Set<String> newKeys = afterContent.keys.toSet()
        ..removeAll(originalContent.keys);
      for (String key in newKeys) {
        afterContent.remove(key);
      }
      Result? result = checkExpectedContentData(afterContent, originalContent);
      if (result != null) return result.copyWithOutput<List<int>?>(null);

      // Check that the result is self-contained.
      result = checkSelfContained(loadedComponent);
      if (result != null) return result.copyWithOutput<List<int>?>(null);

      return new Result<List<int>>.pass(bytes);
    }
  }
  return new Result<List<int>?>.pass(null);
}

Result? checkSelfContained(Component component) {
  Set<Library> got = new Set<Library>.from(component.libraries);
  for (Library lib in component.libraries) {
    for (LibraryDependency dependency in lib.dependencies) {
      if (dependency.importedLibraryReference.node == null ||
          !got.contains(dependency.targetLibrary)) {
        if (dependency.importedLibraryReference.canonicalName
            .toString()
            .startsWith("root::dart:")) {
          continue;
        }
        return Result(
            null,
            IncrementalSerializationError,
            "Component didn't contain ${dependency.importedLibraryReference} "
            "and it should have.");
      }
    }
  }
  return null;
}

void computeAllReachableLibrariesFor(Library lib, Set<Library> allLibraries) {
  Set<Library> libraries = new Set<Library>();
  List<Library> workList = <Library>[];
  allLibraries.add(lib);
  libraries.add(lib);
  workList.add(lib);
  while (workList.isNotEmpty) {
    Library library = workList.removeLast();
    for (LibraryDependency dependency in library.dependencies) {
      if (dependency.targetLibrary.importUri.isScheme("dart")) continue;
      if (libraries.add(dependency.targetLibrary)) {
        workList.add(dependency.targetLibrary);
        allLibraries.add(dependency.targetLibrary);
      }
    }
  }
}

Result? checkExpectedContent(YamlMap world, Component component) {
  if (world["expectedContent"] != null) {
    Map<String, Set<String>> actualContent = buildMapOfContent(component);
    Map expectedContent = world["expectedContent"];
    return checkExpectedContentData(actualContent, expectedContent);
  }
  return null;
}

Result? checkExpectedContentData(
    Map<String, Set<String>> actualContent, Map expectedContent) {
  Result<TestData> createFailureResult() {
    return new Result(
        null,
        ContentDataMismatch,
        "Expected and actual content not the same.\n"
        "Expected $expectedContent.\n"
        "Got $actualContent");
  }

  if (actualContent.length != expectedContent.length) {
    return createFailureResult();
  }
  Set<String> missingKeys = actualContent.keys.toSet()
    ..removeAll(expectedContent.keys);
  if (missingKeys.isNotEmpty) {
    return createFailureResult();
  }
  for (String key in expectedContent.keys) {
    Set<String> expected = new Set<String>.from(expectedContent[key]);
    Set<String> actual = actualContent[key]!.toSet();
    if (expected.length != actual.length) {
      return createFailureResult();
    }
    actual.removeAll(expected);
    if (actual.isNotEmpty) {
      return createFailureResult();
    }
  }
  return null;
}

Map<String, Set<String>> buildMapOfContent(Component component) {
  Map<String, Set<String>> actualContent = new Map<String, Set<String>>();
  for (Library lib in component.libraries) {
    Set<String> libContent =
        actualContent[lib.importUri.toString()] = new Set<String>();
    for (Class c in lib.classes) {
      libContent.add("Class ${c.name}");
    }
    for (Procedure p in lib.procedures) {
      libContent.add("Procedure ${p.name.text}");
    }
    for (Field f in lib.fields) {
      libContent.add("Field ${f.name.text}");
    }
  }
  return actualContent;
}

Result<TestData>? checkNeededDillLibraries(
    YamlMap world, TestData data, Set<Library>? neededDillLibraries, Uri base) {
  if (world["neededDillLibraries"] != null) {
    List<Uri> actualContent = <Uri>[];
    for (Library lib in neededDillLibraries!) {
      if (lib.importUri.isScheme("dart")) continue;
      actualContent.add(lib.importUri);
    }

    List<Uri> expectedContent = <Uri>[];
    for (String entry in world["neededDillLibraries"]) {
      expectedContent.add(base.resolve(entry));
    }

    Result<TestData> createFailureResult() {
      return new Result<TestData>(
          data,
          NeededDillMismatch,
          "Expected and actual content not the same.\n"
          "Expected $expectedContent.\n"
          "Got $actualContent");
    }

    if (actualContent.length != expectedContent.length) {
      return createFailureResult();
    }
    Set<Uri> notInExpected =
        actualContent.toSet().difference(expectedContent.toSet());
    Set<Uri> notInActual =
        expectedContent.toSet().difference(actualContent.toSet());
    if (notInExpected.isNotEmpty) {
      return createFailureResult();
    }
    if (notInActual.isNotEmpty) {
      return createFailureResult();
    }
  }
  return null;
}

String nodeToString(TreeNode node) {
  StringBuffer buffer = new StringBuffer();
  new Printer(buffer, syntheticNames: new NameSystem()).writeNode(node);
  return '$buffer';
}

String componentToStringSdkFiltered(Component component) {
  Component c = new Component();
  List<Uri> dartUris = <Uri>[];
  for (Library lib in component.libraries) {
    if (lib.importUri.isScheme("dart")) {
      dartUris.add(lib.importUri);
    } else {
      c.libraries.add(lib);
    }
  }
  c.setMainMethodAndMode(component.mainMethodName, true, component.mode);
  c.problemsAsJson = component.problemsAsJson;

  StringBuffer s = new StringBuffer();
  s.write(componentToString(c));

  if (dartUris.isNotEmpty) {
    s.writeln("");
    s.writeln("And ${dartUris.length} platform libraries:");
    for (Uri uri in dartUris) {
      s.writeln(" - $uri");
    }
  }

  return s.toString();
}

int countNonSyntheticLibraries(Component c) {
  int result = 0;
  for (Library lib in c.libraries) {
    if (!lib.isSynthetic) result++;
  }
  return result;
}

int countNonSyntheticPlatformLibraries(Component c) {
  int result = 0;
  for (Library lib in c.libraries) {
    if (!lib.isSynthetic && lib.importUri.isScheme("dart")) result++;
  }
  return result;
}

int countSyntheticLibraries(Component c) {
  int result = 0;
  for (Library lib in c.libraries) {
    if (lib.isSynthetic) result++;
  }
  return result;
}

Result<TestData>? performErrorAndWarningCheck(
    YamlMap world,
    TestData data,
    bool gotError,
    Set<String> formattedErrors,
    bool gotWarning,
    Set<String> formattedWarnings) {
  if (world["errors"] == true && !gotError) {
    return new Result<TestData>(
        data, MissingErrors, "Expected error, but didn't get any.");
  } else if (world["errors"] != true && gotError) {
    return new Result<TestData>(
        data, UnexpectedErrors, "Got unexpected error(s): $formattedErrors.");
  }
  if (world["warnings"] == true && !gotWarning) {
    return new Result<TestData>(
        data, MissingWarnings, "Expected warning, but didn't get any.");
  } else if (world["warnings"] != true && gotWarning) {
    return new Result<TestData>(data, UnexpectedWarnings,
        "Got unexpected warnings(s): $formattedWarnings.");
  }
  return null;
}

void checkIsEqual(List<int> a, List<int> b) {
  int length = a.length;
  if (b.length < length) {
    length = b.length;
  }
  for (int i = 0; i < length; ++i) {
    if (a[i] != b[i]) {
      print("Data differs at byte ${i + 1}.");

      StringBuffer message = new StringBuffer();
      message.writeln("Data differs at byte ${i + 1}.");
      message.writeln("");
      message.writeln("Will try to find more useful information:");

      final String repoDir = computeRepoDir();
      File binaryMd = new File("$repoDir/pkg/kernel/binary.md");
      String binaryMdContent = binaryMd.readAsStringSync();

      DillComparer dillComparer = new DillComparer();
      if (dillComparer.compare(a, b, binaryMdContent, message)) {
        message.writeln(
            "Somehow the two different byte-lists compared to the same.");
      }

      Expect.fail(message.toString());
    }
  }
  Expect.equals(a.length, b.length);
}

CompilerOptions getOptions({Target? target, String? sdkSummary}) {
  target ??= new VmTarget(new TargetFlags());
  sdkSummary ??= 'vm_platform_strong.dill';
  final Uri sdkRoot = computePlatformBinariesLocation(forceBuildDir: true);
  CompilerOptions options = new CompilerOptions()
    ..sdkRoot = sdkRoot
    ..target = target
    ..librariesSpecificationUri = Uri.base.resolve("sdk/lib/libraries.json")
    ..omitPlatform = true
    ..onDiagnostic = (DiagnosticMessage message) {
      if (message.severity == Severity.error ||
          message.severity == Severity.warning) {
        Expect.fail(
            "Unexpected error: ${message.plainTextFormatted.join('\n')}");
      }
    }
    ..sdkSummary = sdkRoot.resolve(sdkSummary)
    ..environmentDefines = const {};
  return options;
}

Future<bool> normalCompile(Uri input, Uri output,
    {CompilerOptions? options}) async {
  options ??= getOptions();
  TestIncrementalCompiler compiler =
      new TestIncrementalCompiler(options, input);
  List<int> bytes =
      await normalCompileToBytes(input, options: options, compiler: compiler);
  new File.fromUri(output).writeAsBytesSync(bytes);
  return compiler.initializedFromDillForTesting;
}

Future<List<int>> normalCompileToBytes(Uri input,
    {CompilerOptions? options, IncrementalCompiler? compiler}) async {
  Component component = await normalCompileToComponent(input,
      options: options, compiler: compiler);
  return util.postProcess(component);
}

Future<Component> normalCompileToComponent(Uri input,
    {CompilerOptions? options, IncrementalCompiler? compiler}) async {
  Component component =
      await normalCompilePlain(input, options: options, compiler: compiler);
  util.throwOnEmptyMixinBodies(component);
  await util.throwOnInsufficientUriToSource(component);
  return component;
}

Future<Component> normalCompilePlain(Uri input,
    {CompilerOptions? options, IncrementalCompiler? compiler}) async {
  options ??= getOptions();
  compiler ??= new TestIncrementalCompiler(options, input);
  return (await compiler.computeDelta()).component;
}

Future<bool> initializedCompile(
    Uri input, Uri output, Uri initializeWith, List<Uri> invalidateUris,
    {CompilerOptions? options}) async {
  options ??= getOptions();
  TestIncrementalCompiler compiler =
      new TestIncrementalCompiler(options, input, initializeWith);
  for (Uri invalidateUri in invalidateUris) {
    compiler.invalidate(invalidateUri);
  }
  IncrementalCompilerResult initializedCompilerResult =
      await compiler.computeDelta();
  Component initializedComponent = initializedCompilerResult.component;
  util.throwOnEmptyMixinBodies(initializedComponent);
  await util.throwOnInsufficientUriToSource(initializedComponent);
  bool result = compiler.initializedFromDillForTesting;
  new File.fromUri(output)
      .writeAsBytesSync(util.postProcess(initializedComponent));
  int actuallyInvalidatedCount = compiler
          .getFilteredInvalidatedImportUrisForTesting(invalidateUris)
          ?.length ??
      0;
  if (result && actuallyInvalidatedCount < invalidateUris.length) {
    Expect.fail("Expected at least ${invalidateUris.length} invalidated uris, "
        "got $actuallyInvalidatedCount");
  }

  IncrementalCompilerResult initializedFullCompilerResult =
      await compiler.computeDelta(fullComponent: true);
  Component initializedFullComponent = initializedFullCompilerResult.component;
  util.throwOnEmptyMixinBodies(initializedFullComponent);
  await util.throwOnInsufficientUriToSource(initializedFullComponent);
  Expect.equals(initializedComponent.libraries.length,
      initializedFullComponent.libraries.length);
  Expect.equals(initializedComponent.uriToSource.length,
      initializedFullComponent.uriToSource.length);

  for (Uri invalidateUri in invalidateUris) {
    compiler.invalidate(invalidateUri);
  }

  IncrementalCompilerResult partialResult = await compiler.computeDelta();
  Component partialComponent = partialResult.component;
  util.throwOnEmptyMixinBodies(partialComponent);
  await util.throwOnInsufficientUriToSource(partialComponent);
  actuallyInvalidatedCount = (compiler
          .getFilteredInvalidatedImportUrisForTesting(invalidateUris)
          ?.length ??
      0);
  if (actuallyInvalidatedCount < invalidateUris.length) {
    Expect.fail("Expected at least ${invalidateUris.length} invalidated uris, "
        "got $actuallyInvalidatedCount");
  }

  IncrementalCompilerResult emptyResult = await compiler.computeDelta();
  Component emptyComponent = emptyResult.component;
  util.throwOnEmptyMixinBodies(emptyComponent);
  await util.throwOnInsufficientUriToSource(emptyComponent);

  List<Uri> fullLibUris =
      initializedComponent.libraries.map((lib) => lib.importUri).toList();
  List<Uri> partialLibUris =
      partialComponent.libraries.map((lib) => lib.importUri).toList();
  List<Uri> emptyLibUris =
      emptyComponent.libraries.map((lib) => lib.importUri).toList();

  Expect.isTrue(fullLibUris.length > partialLibUris.length ||
      partialLibUris.length == invalidateUris.length);
  Expect.isTrue(partialLibUris.isNotEmpty || invalidateUris.isEmpty);

  Expect.isTrue(emptyLibUris.isEmpty);

  return result;
}

class TestIncrementalCompiler extends IncrementalCompiler {
  @override
  final TestRecorderForTesting recorderForTesting =
      new TestRecorderForTesting();
  final Uri entryPoint;

  /// Filter out the automatically added entryPoint, unless it's explicitly
  /// specified as being invalidated.
  /// Also filter out uris with "nonexisting.dart" in the name as synthetic
  /// libraries are invalidated automatically too.
  /// This is not perfect, but works for what it's currently used for.
  Set<Uri>? getFilteredInvalidatedImportUrisForTesting(
      List<Uri> invalidatedUris) {
    if (recorderForTesting.invalidatedImportUrisForTesting == null) return null;

    Set<String> invalidatedFilenames =
        invalidatedUris.map((uri) => uri.pathSegments.last).toSet();
    Set<Uri> result = new Set<Uri>();
    for (Uri uri in recorderForTesting.invalidatedImportUrisForTesting!) {
      if (uri.pathSegments.isNotEmpty &&
          uri.pathSegments.last == "nonexisting.dart") {
        continue;
      }
      if (invalidatedFilenames.contains(entryPoint.pathSegments.last) ||
          invalidatedFilenames.contains(uri.pathSegments.last)) {
        result.add(uri);
      }
    }

    return result.isEmpty ? null : result;
  }

  TestIncrementalCompiler(CompilerOptions options, this.entryPoint,
      [Uri? initializeFrom,
      bool? outlineOnly,
      IncrementalSerializer? incrementalSerializer])
      : super(
            new CompilerContext(
                new ProcessedOptions(options: options, inputs: [entryPoint])),
            initializeFrom,
            outlineOnly,
            incrementalSerializer);

  TestIncrementalCompiler.fromComponent(CompilerOptions options,
      this.entryPoint, Component? componentToInitializeFrom,
      [bool? outlineOnly, IncrementalSerializer? incrementalSerializer])
      : super.fromComponent(
            new CompilerContext(
                new ProcessedOptions(options: options, inputs: [entryPoint])),
            componentToInitializeFrom,
            outlineOnly,
            incrementalSerializer);

  @override
  Future<IncrementalCompilerResult> computeDelta(
      {List<Uri>? entryPoints,
      bool fullComponent = false,
      bool trackNeededDillLibraries: false,
      bool? simulateTransformer}) async {
    IncrementalCompilerResult result = await super.computeDelta(
        entryPoints: entryPoints,
        fullComponent: fullComponent,
        trackNeededDillLibraries: trackNeededDillLibraries);

    // We should at least have the SDK builders available. Slight smoke test.
    if (!dillTargetForTesting!.loader.libraryImportUris
        .map((uri) => uri.toString())
        .contains("dart:core")) {
      throw "Loaders builder should contain the sdk, "
          "but didn't even contain dart:core.";
    }

    if (simulateTransformer == true) {
      doSimulateTransformer(result.component);
    }
    return result;
  }
}

class TestRecorderForTesting extends RecorderForTesting {
  Set<Uri>? invalidatedImportUrisForTesting;
  int? rebuildBodiesCount;

  @override
  void recordInvalidatedImportUris(List<Uri> uris) {
    invalidatedImportUrisForTesting = uris.isEmpty ? null : uris.toSet();
  }

  @override
  void recordNonFullComponent(Component component) {
    // It should at least contain the sdk. Slight smoke test.
    if (!component.libraries
        .map((lib) => lib.importUri.toString())
        .contains("dart:core")) {
      throw "Loaders builder should contain the sdk, "
          "but didn't even contain dart:core.";
    }
  }

  @override
  void recordRebuildBodiesCount(int count) {
    rebuildBodiesCount = count;
  }

  @override
  void recordTemporaryFile(Uri uri) {
    File f = new File.fromUri(uri);
    if (f.existsSync()) f.deleteSync();
  }
}

void doSimulateTransformer(Component c) {
  for (Library lib in c.libraries) {
    if (lib.fields
        .where((f) => f.name.text == "unique_SimulateTransformer")
        .toList()
        .isNotEmpty) continue;
    Name fieldName = new Name("unique_SimulateTransformer");
    Field field = new Field.immutable(fieldName,
        isFinal: true,
        fieldReference: lib.reference.canonicalName
            ?.getChildFromFieldWithName(fieldName)
            .reference,
        getterReference: lib.reference.canonicalName
            ?.getChildFromFieldGetterWithName(fieldName)
            .reference,
        fileUri: lib.fileUri);
    lib.addField(field);
    for (Class c in lib.classes) {
      if (c.fields
          .where((f) => f.name.text == "unique_SimulateTransformer")
          .toList()
          .isNotEmpty) continue;
      fieldName = new Name("unique_SimulateTransformer");
      field = new Field.immutable(fieldName,
          isFinal: true,
          fieldReference: lib.reference.canonicalName
              ?.getChildFromFieldWithName(fieldName)
              .reference,
          getterReference: c.reference.canonicalName
              ?.getChildFromFieldGetterWithName(fieldName)
              .reference,
          fileUri: c.fileUri);
      c.addField(field);
    }
  }
}

class TestMemoryFileSystem extends MemoryFileSystem {
  TestMemoryFileSystem(Uri currentDirectory) : super(currentDirectory);

  @override
  MemoryFileSystemEntity entityForUri(Uri uri) {
    // Try to "sanitize" the uri as a real file system does, namely
    // "a/b.dart" and "a//b.dart" returns the same file.
    if (uri.pathSegments.contains("")) {
      Uri newUri = uri.replace(
          pathSegments: uri.pathSegments.where((element) => element != ""));
      return super.entityForUri(newUri);
    }
    return super.entityForUri(uri);
  }
}
