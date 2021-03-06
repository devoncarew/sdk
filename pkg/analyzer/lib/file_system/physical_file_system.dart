// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analyzer.file_system.physical_file_system;

import 'dart:async';
import 'dart:core';
import 'dart:io' as io;

import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:analyzer/src/source/source_resource.dart';
import 'package:analyzer/src/util/absolute_path.dart';
import 'package:isolate/isolate_runner.dart';
import 'package:path/path.dart';
import 'package:watcher/watcher.dart';

/**
 * Return modification times for every file path in [paths].
 *
 * If a path is `null`, the modification time is also `null`.
 *
 * If any exception happens, the file is considered as a not existing and
 * `-1` is its modification time.
 */
List<int> _pathsToTimes(List<String> paths) {
  return paths.map((path) {
    if (path != null) {
      try {
        io.File file = new io.File(path);
        return file.lastModifiedSync().millisecondsSinceEpoch;
      } catch (_) {
        return -1;
      }
    } else {
      return null;
    }
  }).toList();
}

/**
 * A `dart:io` based implementation of [ResourceProvider].
 */
class PhysicalResourceProvider implements ResourceProvider {
  static final FileReadMode NORMALIZE_EOL_ALWAYS =
      (String string) => string.replaceAll(new RegExp('\r\n?'), '\n');

  static final PhysicalResourceProvider INSTANCE =
      new PhysicalResourceProvider(null);

  /**
   * The name of the directory containing plugin specific subfolders used to
   * store data across sessions.
   */
  static final String SERVER_DIR = ".dartServer";

  static _SingleIsolateRunnerProvider pathsToTimesIsolateProvider =
      new _SingleIsolateRunnerProvider();

  @override
  final AbsolutePathContext absolutePathContext =
      new AbsolutePathContext(io.Platform.isWindows);

  PhysicalResourceProvider(FileReadMode fileReadMode) {
    if (fileReadMode != null) {
      FileBasedSource.fileReadMode = fileReadMode;
    }
  }

  @override
  Context get pathContext => io.Platform.isWindows ? windows : posix;

  @override
  File getFile(String path) {
    path = normalize(path);
    return new _PhysicalFile(new io.File(path));
  }

  @override
  Folder getFolder(String path) {
    path = normalize(path);
    return new _PhysicalFolder(new io.Directory(path));
  }

  @override
  Future<List<int>> getModificationTimes(List<Source> sources) async {
    List<String> paths = sources.map((source) => source.fullName).toList();
    IsolateRunner runner = await pathsToTimesIsolateProvider.get();
    return runner.run(_pathsToTimes, paths);
  }

  @override
  Resource getResource(String path) {
    if (io.FileSystemEntity.isDirectorySync(path)) {
      return getFolder(path);
    } else {
      return getFile(path);
    }
  }

  @override
  Folder getStateLocation(String pluginId) {
    String home;
    if (io.Platform.isWindows) {
      home = io.Platform.environment['LOCALAPPDATA'];
    } else {
      home = io.Platform.environment['HOME'];
    }
    if (home != null && io.FileSystemEntity.isDirectorySync(home)) {
      io.Directory directory =
          new io.Directory(join(home, SERVER_DIR, pluginId));
      directory.createSync(recursive: true);
      return new _PhysicalFolder(directory);
    }
    return null;
  }
}

/**
 * A `dart:io` based implementation of [File].
 */
class _PhysicalFile extends _PhysicalResource implements File {
  _PhysicalFile(io.File file) : super(file);

  @override
  Stream<WatchEvent> get changes => new FileWatcher(_entry.path).events;

  @override
  int get lengthSync {
    try {
      return _file.lengthSync();
    } on io.FileSystemException catch (exception) {
      throw new FileSystemException(exception.path, exception.message);
    }
  }

  @override
  int get modificationStamp {
    try {
      return _file.lastModifiedSync().millisecondsSinceEpoch;
    } on io.FileSystemException catch (exception) {
      throw new FileSystemException(exception.path, exception.message);
    }
  }

  /**
   * Return the underlying file being represented by this wrapper.
   */
  io.File get _file => _entry as io.File;

  @override
  Source createSource([Uri uri]) {
    return new FileSource(this, uri ?? pathContext.toUri(path));
  }

  @override
  bool isOrContains(String path) {
    return path == this.path;
  }

  @override
  List<int> readAsBytesSync() {
    _throwIfWindowsDeviceDriver();
    try {
      return _file.readAsBytesSync();
    } on io.FileSystemException catch (exception) {
      throw new FileSystemException(exception.path, exception.message);
    }
  }

  @override
  String readAsStringSync() {
    _throwIfWindowsDeviceDriver();
    try {
      return FileBasedSource.fileReadMode(_file.readAsStringSync());
    } on io.FileSystemException catch (exception) {
      throw new FileSystemException(exception.path, exception.message);
    }
  }

  @override
  File renameSync(String newPath) {
    try {
      return new _PhysicalFile(_file.renameSync(newPath));
    } on io.FileSystemException catch (exception) {
      throw new FileSystemException(exception.path, exception.message);
    }
  }

  @override
  File resolveSymbolicLinksSync() {
    try {
      return new _PhysicalFile(new io.File(_file.resolveSymbolicLinksSync()));
    } on io.FileSystemException catch (exception) {
      throw new FileSystemException(exception.path, exception.message);
    }
  }

  @override
  Uri toUri() => new Uri.file(path);

  @override
  void writeAsBytesSync(List<int> bytes) {
    try {
      _file.writeAsBytesSync(bytes);
    } on io.FileSystemException catch (exception) {
      throw new FileSystemException(exception.path, exception.message);
    }
  }

  @override
  void writeAsStringSync(String content) {
    try {
      _file.writeAsStringSync(content);
    } on io.FileSystemException catch (exception) {
      throw new FileSystemException(exception.path, exception.message);
    }
  }
}

/**
 * A `dart:io` based implementation of [Folder].
 */
class _PhysicalFolder extends _PhysicalResource implements Folder {
  _PhysicalFolder(io.Directory directory) : super(directory);

  @override
  Stream<WatchEvent> get changes => new DirectoryWatcher(_entry.path)
      .events
      .handleError(() {}, test: (error) => error is io.FileSystemException);

  /**
   * Return the underlying file being represented by this wrapper.
   */
  io.Directory get _directory => _entry as io.Directory;

  @override
  String canonicalizePath(String relPath) {
    return normalize(join(path, relPath));
  }

  @override
  bool contains(String path) {
    return absolutePathContext.isWithin(this.path, path);
  }

  @override
  Resource getChild(String relPath) {
    String canonicalPath = canonicalizePath(relPath);
    return PhysicalResourceProvider.INSTANCE.getResource(canonicalPath);
  }

  @override
  _PhysicalFile getChildAssumingFile(String relPath) {
    String canonicalPath = canonicalizePath(relPath);
    io.File file = new io.File(canonicalPath);
    return new _PhysicalFile(file);
  }

  @override
  _PhysicalFolder getChildAssumingFolder(String relPath) {
    String canonicalPath = canonicalizePath(relPath);
    io.Directory directory = new io.Directory(canonicalPath);
    return new _PhysicalFolder(directory);
  }

  @override
  List<Resource> getChildren() {
    try {
      List<Resource> children = <Resource>[];
      io.Directory directory = _entry as io.Directory;
      List<io.FileSystemEntity> entries = directory.listSync(recursive: false);
      int numEntries = entries.length;
      for (int i = 0; i < numEntries; i++) {
        io.FileSystemEntity entity = entries[i];
        if (entity is io.Directory) {
          children.add(new _PhysicalFolder(entity));
        } else if (entity is io.File) {
          children.add(new _PhysicalFile(entity));
        }
      }
      return children;
    } on io.FileSystemException catch (exception) {
      throw new FileSystemException(exception.path, exception.message);
    }
  }

  @override
  bool isOrContains(String path) {
    if (path == this.path) {
      return true;
    }
    return contains(path);
  }

  @override
  Folder resolveSymbolicLinksSync() {
    try {
      return new _PhysicalFolder(
          new io.Directory(_directory.resolveSymbolicLinksSync()));
    } on io.FileSystemException catch (exception) {
      throw new FileSystemException(exception.path, exception.message);
    }
  }

  @override
  Uri toUri() => new Uri.directory(path);
}

/**
 * A `dart:io` based implementation of [Resource].
 */
abstract class _PhysicalResource implements Resource {
  final io.FileSystemEntity _entry;

  _PhysicalResource(this._entry);

  AbsolutePathContext get absolutePathContext =>
      PhysicalResourceProvider.INSTANCE.absolutePathContext;

  @override
  bool get exists => _entry.existsSync();

  @override
  get hashCode => path.hashCode;

  @override
  Folder get parent {
    String parentPath = absolutePathContext.dirname(path);
    if (parentPath == path) {
      return null;
    }
    return new _PhysicalFolder(new io.Directory(parentPath));
  }

  @override
  String get path => _entry.absolute.path;

  /**
   * Return the path context used by this resource provider.
   */
  Context get pathContext => io.Platform.isWindows ? windows : posix;

  @override
  String get shortName => absolutePathContext.basename(path);

  @override
  bool operator ==(other) {
    if (runtimeType != other.runtimeType) {
      return false;
    }
    return path == other.path;
  }

  @override
  void delete() {
    try {
      _entry.deleteSync(recursive: true);
    } on io.FileSystemException catch (exception) {
      throw new FileSystemException(exception.path, exception.message);
    }
  }

  @override
  String toString() => path;

  /**
   * If the operating system is Windows and the resource references one of the
   * device drivers, throw a [FileSystemException].
   *
   * https://support.microsoft.com/en-us/kb/74496
   */
  void _throwIfWindowsDeviceDriver() {
    if (io.Platform.isWindows) {
      String shortName = this.shortName.toUpperCase();
      if (shortName == r'CON' ||
          shortName == r'PRN' ||
          shortName == r'AUX' ||
          shortName == r'CLOCK$' ||
          shortName == r'NUL' ||
          shortName == r'COM1' ||
          shortName == r'LPT1' ||
          shortName == r'LPT2' ||
          shortName == r'LPT3' ||
          shortName == r'COM2' ||
          shortName == r'COM3' ||
          shortName == r'COM4') {
        throw new FileSystemException(
            path, 'Windows device drivers cannot be read.');
      }
    }
  }
}

/**
 * This class encapsulates logic for creating a single [IsolateRunner].
 */
class _SingleIsolateRunnerProvider {
  bool _isSpawning = false;
  IsolateRunner _runner;

  /**
   * Complete with the only [IsolateRunner] instance.
   */
  Future<IsolateRunner> get() async {
    if (_runner != null) {
      return _runner;
    }
    if (_isSpawning) {
      Completer<IsolateRunner> completer = new Completer<IsolateRunner>();
      new Timer.periodic(new Duration(milliseconds: 10), (Timer timer) {
        if (_runner != null) {
          completer.complete(_runner);
          timer.cancel();
        }
      });
      return completer.future;
    }
    _isSpawning = true;
    _runner = await IsolateRunner.spawn();
    return _runner;
  }
}
