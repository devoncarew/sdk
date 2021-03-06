// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Entity model for elements derived from Kernel IR.

import '../elements/elements.dart';
import '../elements/entities.dart';

class KLibrary implements LibraryEntity {
  /// Library index used for fast lookup in [KernelWorldBuilder].
  final int libraryIndex;
  final String name;
  final String libraryName;

  KLibrary(this.libraryIndex, this.name, this.libraryName);

  String toString() => 'library($name)';
}

class KClass implements ClassEntity {
  final String name;

  KClass(this.name);

  @override
  bool get isClosure => false;

  String toString() => 'class($name)';
}

abstract class KMember implements MemberEntity {
  final KClass enclosingClass;
  final Name _name;
  final bool _isStatic;

  KMember(this.enclosingClass, this._name, {bool isStatic: false})
      : _isStatic = isStatic;

  String get name => _name.text;

  @override
  bool get isAssignable => false;

  @override
  bool get isSetter => false;

  @override
  bool get isGetter => false;

  @override
  bool get isFunction => false;

  @override
  bool get isField => false;

  @override
  bool get isConstructor => false;

  @override
  bool get isInstanceMember => enclosingClass != null && !_isStatic;

  @override
  bool get isStatic => enclosingClass != null && _isStatic;

  @override
  bool get isTopLevel => enclosingClass == null;

  String get _kind;

  String toString() =>
      '$_kind(${enclosingClass != null ? '${enclosingClass.name}.' : ''}$name)';
}

abstract class KFunction extends KMember implements FunctionEntity {
  KFunction(KClass enclosingClass, Name name, {bool isStatic: false})
      : super(enclosingClass, name, isStatic: isStatic);
}

abstract class KConstructor extends KFunction implements ConstructorEntity {
  KConstructor(KClass enclosingClass, Name name) : super(enclosingClass, name);

  @override
  bool get isConstructor => true;

  @override
  bool get isInstanceMember => false;

  @override
  bool get isStatic => false;

  @override
  bool get isTopLevel => false;

  String get _kind => 'constructor';
}

class KGenerativeConstructor extends KConstructor {
  KGenerativeConstructor(KClass enclosingClass, Name name)
      : super(enclosingClass, name);

  @override
  bool get isFactoryConstructor => false;

  @override
  bool get isGenerativeConstructor => true;
}

class KFactoryConstructor extends KConstructor {
  KFactoryConstructor(KClass enclosingClass, Name name)
      : super(enclosingClass, name);

  @override
  bool get isFactoryConstructor => true;

  @override
  bool get isGenerativeConstructor => false;
}

class KMethod extends KFunction {
  KMethod(KClass enclosingClass, Name name, {bool isStatic})
      : super(enclosingClass, name, isStatic: isStatic);

  @override
  bool get isFunction => true;

  String get _kind => 'method';
}

class KGetter extends KFunction {
  KGetter(KClass enclosingClass, Name name, {bool isStatic})
      : super(enclosingClass, name, isStatic: isStatic);

  @override
  bool get isGetter => true;

  String get _kind => 'getter';
}

class KSetter extends KFunction {
  KSetter(KClass enclosingClass, Name name, {bool isStatic})
      : super(enclosingClass, name, isStatic: isStatic);

  @override
  bool get isAssignable => true;

  @override
  bool get isSetter => true;

  String get _kind => 'setter';
}

class KField extends KMember implements FieldEntity {
  final bool isAssignable;

  KField(KClass enclosingClass, Name name, {bool isStatic, this.isAssignable})
      : super(enclosingClass, name, isStatic: isStatic);

  @override
  bool get isField => true;

  String get _kind => 'field';
}

class KTypeVariable implements TypeVariableEntity {
  final Entity typeDeclaration;
  final String name;
  final int index;

  KTypeVariable(this.typeDeclaration, this.name, this.index);
}

class KLocalFunction implements Local {
  final String name;
  final MemberEntity memberContext;
  final Entity executableContext;

  KLocalFunction(this.name, this.memberContext, this.executableContext);
}
