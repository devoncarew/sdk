// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart' as ir;

import '../common.dart';
import '../common/names.dart';
import '../core_types.dart';
import '../elements/elements.dart';
import '../elements/entities.dart';
import '../elements/types.dart';
import '../native/native.dart' as native;
import 'element_adapter.dart';
import 'elements.dart';

/// World builder used for creating elements and types corresponding to Kernel
/// IR nodes.
// TODO(johnniwinther): Implement [ResolutionWorldBuilder].
class KernelWorldBuilder extends KernelElementAdapterMixin {
  CommonElements _commonElements;
  final DiagnosticReporter reporter;

  DartTypeConverter _typeConverter;

  /// Library environment. Used for fast lookup.
  KEnv _env;

  /// List of library environments by `KLibrary.libraryIndex`. This is used for
  /// fast lookup into library classes and members.
  List<KLibraryEnv> _libraryEnvs = <KLibraryEnv>[];

  Map<ir.Library, KLibrary> _libraryMap = <ir.Library, KLibrary>{};
  Map<ir.Class, KClass> _classMap = <ir.Class, KClass>{};
  Map<ir.TypeParameter, KTypeVariable> _typeVariableMap =
      <ir.TypeParameter, KTypeVariable>{};
  Map<ir.Member, KConstructor> _constructorMap = <ir.Member, KConstructor>{};
  Map<ir.Procedure, KFunction> _methodMap = <ir.Procedure, KFunction>{};
  Map<ir.Field, KField> _fieldMap = <ir.Field, KField>{};
  Map<ir.TreeNode, KLocalFunction> _localFunctionMap =
      <ir.TreeNode, KLocalFunction>{};

  KernelWorldBuilder(this.reporter, ir.Program program)
      : _env = new KEnv(program) {
    _commonElements = new KernelCommonElements(this);
    _typeConverter = new DartTypeConverter(this);
  }

  CommonElements get commonElements => _commonElements;

  LibraryEntity lookupLibrary(Uri uri) {
    KLibraryEnv libraryEnv = _env.lookupLibrary(uri);
    return _getLibrary(libraryEnv.library, libraryEnv);
  }

  KLibrary _getLibrary(ir.Library node, [KLibraryEnv libraryEnv]) {
    return _libraryMap.putIfAbsent(node, () {
      _libraryEnvs.add(libraryEnv ?? _env.lookupLibrary(node.importUri));
      return new KLibrary(_libraryMap.length, node.name, node.fileUri);
    });
  }

  ClassEntity lookupClass(KLibrary library, String name) {
    KLibraryEnv libraryEnv = _libraryEnvs[library.libraryIndex];
    KClassEnv classEnv = libraryEnv.lookupClass(name);
    return _getClass(classEnv.cls, classEnv);
  }

  KClass _getClass(ir.Class node, [KClassEnv classEnv]) {
    return _classMap.putIfAbsent(node, () {
      return new KClass(node.name);
    });
  }

  KTypeVariable _getTypeVariable(ir.TypeParameter node) {
    return _typeVariableMap.putIfAbsent(node, () {
      if (node.parent is ir.Class) {
        ir.Class cls = node.parent;
        int index = cls.typeParameters.indexOf(node);
        return new KTypeVariable(_getClass(cls), node.name, index);
      }
      if (node.parent is ir.FunctionNode) {
        ir.FunctionNode func = node.parent;
        int index = func.typeParameters.indexOf(node);
        if (func.parent is ir.Constructor) {
          ir.Constructor constructor = func.parent;
          ir.Class cls = constructor.enclosingClass;
          return _getTypeVariable(cls.typeParameters[index]);
        }
        if (func.parent is ir.Procedure) {
          ir.Procedure procedure = func.parent;
          if (procedure.kind == ir.ProcedureKind.Factory) {
            ir.Class cls = procedure.enclosingClass;
            return _getTypeVariable(cls.typeParameters[index]);
          } else {
            return new KTypeVariable(_getMethod(procedure), node.name, index);
          }
        }
      }
      throw new UnsupportedError('Unsupported type parameter type node $node.');
    });
  }

  KConstructor _getConstructor(ir.Member node) {
    return _constructorMap.putIfAbsent(node, () {
      if (node is ir.Constructor) {
        return new KGenerativeConstructor(
            _getClass(node.enclosingClass), getName(node.name));
      } else {
        return new KFactoryConstructor(
            _getClass(node.enclosingClass), getName(node.name));
      }
    });
  }

  KFunction _getMethod(ir.Procedure node) {
    return _methodMap.putIfAbsent(node, () {
      KClass enclosingClass =
          node.enclosingClass != null ? _getClass(node.enclosingClass) : null;
      Name name = getName(node.name);
      bool isStatic = node.isStatic;
      switch (node.kind) {
        case ir.ProcedureKind.Factory:
          throw new UnsupportedError("Cannot create method from factory.");
        case ir.ProcedureKind.Getter:
          return new KGetter(enclosingClass, name, isStatic: isStatic);
        case ir.ProcedureKind.Method:
        case ir.ProcedureKind.Operator:
          return new KMethod(enclosingClass, name, isStatic: isStatic);
        case ir.ProcedureKind.Setter:
          return new KSetter(enclosingClass, getName(node.name).setter,
              isStatic: isStatic);
      }
    });
  }

  KField _getField(ir.Field node) {
    return _fieldMap.putIfAbsent(node, () {
      KClass enclosingClass =
          node.enclosingClass != null ? _getClass(node.enclosingClass) : null;
      Name name = getName(node.name);
      bool isStatic = node.isStatic;
      return new KField(enclosingClass, name,
          isStatic: isStatic, isAssignable: node.isMutable);
    });
  }

  KLocalFunction _getLocal(ir.TreeNode node) {
    return _localFunctionMap.putIfAbsent(node, () {
      MemberEntity memberContext;
      Entity executableContext;
      ir.TreeNode parent = node.parent;
      while (parent != null) {
        if (parent is ir.Member) {
          executableContext = memberContext = getMember(parent);
          break;
        }
        if (parent is ir.FunctionDeclaration ||
            parent is ir.FunctionExpression) {
          KLocalFunction localFunction = _getLocal(parent);
          executableContext = localFunction;
          memberContext = localFunction.memberContext;
          break;
        }
        parent = parent.parent;
      }
      String name;
      if (node is ir.FunctionDeclaration) {
        name = node.variable.name;
      }
      return new KLocalFunction(name, memberContext, executableContext);
    });
  }

  @override
  DartType getDartType(ir.DartType type) => _typeConverter.convert(type);

  @override
  InterfaceType createInterfaceType(
      ir.Class cls, List<ir.DartType> typeArguments) {
    return new InterfaceType(getClass(cls), getDartTypes(typeArguments));
  }

  @override
  InterfaceType getInterfaceType(ir.InterfaceType type) =>
      _typeConverter.convert(type);

  @override
  List<DartType> getDartTypes(List<ir.DartType> types) {
    // TODO(johnniwinther): Add the type argument to the list literal when we
    // no longer use resolution types.
    List<DartType> list = /*<DartType>*/ [];
    types.forEach((ir.DartType type) {
      list.add(getDartType(type));
    });
    return list;
  }

  @override
  InterfaceType getThisType(ClassEntity cls) {
    throw new UnimplementedError('KernelWorldBuilder.getThisType');
  }

  @override
  InterfaceType getRawType(ClassEntity cls) {
    throw new UnimplementedError('KernelWorldBuilder.getRawType');
  }

  @override
  InterfaceType getInterfaceTypeForJsInterceptorCall(ir.StaticInvocation node) {
    throw new UnimplementedError('KernelWorldBuilder.getDartType');
  }

  @override
  native.NativeBehavior getNativeBehaviorForJsEmbeddedGlobalCall(
      ir.StaticInvocation node) {
    throw new UnimplementedError('KernelWorldBuilder.getDartType');
  }

  @override
  native.NativeBehavior getNativeBehaviorForJsBuiltinCall(
      ir.StaticInvocation node) {
    throw new UnimplementedError('KernelWorldBuilder.getDartType');
  }

  @override
  native.NativeBehavior getNativeBehaviorForJsCall(ir.StaticInvocation node) {
    throw new UnimplementedError('KernelWorldBuilder.getDartType');
  }

  @override
  native.NativeBehavior getNativeBehaviorForMethod(ir.Procedure procedure) {
    throw new UnimplementedError('KernelWorldBuilder.getDartType');
  }

  @override
  native.NativeBehavior getNativeBehaviorForFieldStore(ir.Field field) {
    throw new UnimplementedError('KernelWorldBuilder.getDartType');
  }

  @override
  native.NativeBehavior getNativeBehaviorForFieldLoad(ir.Field field) {
    throw new UnimplementedError('KernelWorldBuilder.getDartType');
  }

  LibraryEntity getLibrary(ir.Library node) => _getLibrary(node);

  @override
  Local getLocalFunction(ir.TreeNode node) => _getLocal(node);

  @override
  ClassEntity getClass(ir.Class node) => _getClass(node);

  @override
  FieldEntity getField(ir.Field node) => _getField(node);

  TypeVariableEntity getTypeVariable(ir.TypeParameter node) =>
      _getTypeVariable(node);

  @override
  FunctionEntity getMethod(ir.Procedure node) => _getMethod(node);

  @override
  MemberEntity getMember(ir.Member node) {
    if (node is ir.Field) {
      return _getField(node);
    } else if (node is ir.Constructor) {
      return _getConstructor(node);
    } else if (node is ir.Procedure) {
      if (node.kind == ir.ProcedureKind.Factory) {
        return _getConstructor(node);
      } else {
        return _getMethod(node);
      }
    }
    throw new UnsupportedError("Unexpected member: $node");
  }

  @override
  FunctionEntity getConstructor(ir.Member node) => _getConstructor(node);
}

/// Environment for fast lookup of program libraries.
class KEnv {
  final ir.Program program;

  Map<Uri, KLibraryEnv> _libraryMap;

  KEnv(this.program);

  /// Return the [KLibraryEnv] for the library with the canonical [uri].
  KLibraryEnv lookupLibrary(Uri uri) {
    if (_libraryMap == null) {
      _libraryMap = <Uri, KLibraryEnv>{};
      for (ir.Library library in program.libraries) {
        _libraryMap[library.importUri] = new KLibraryEnv(library);
      }
    }
    return _libraryMap[uri];
  }
}

/// Environment for fast lookup of library classes and members.
// TODO(johnniwinther): Add member lookup.
class KLibraryEnv {
  final ir.Library library;

  Map<String, KClassEnv> _classMap;

  KLibraryEnv(this.library);

  /// Return the [KClassEnv] for the class [name] in [library].
  KClassEnv lookupClass(String name) {
    if (_classMap == null) {
      _classMap = <String, KClassEnv>{};
      for (ir.Class cls in library.classes) {
        _classMap[cls.name] = new KClassEnv(cls);
      }
    }
    return _classMap[name];
  }
}

/// Environment for fast lookup of class members.
// TODO(johnniwinther): Add member lookup.
class KClassEnv {
  final ir.Class cls;

  KClassEnv(this.cls);
}

/// [CommonElements] implementation based on [KernelWorldBuilder].
class KernelCommonElements extends CommonElementsMixin {
  final KernelWorldBuilder worldBuilder;

  KernelCommonElements(this.worldBuilder);

  @override
  LibraryEntity get coreLibrary {
    return worldBuilder.lookupLibrary(Uris.dart_core);
  }

  @override
  InterfaceType createInterfaceType(
      ClassEntity cls, List<DartType> typeArguments) {
    return new InterfaceType(cls, typeArguments);
  }

  @override
  InterfaceType getRawType(ClassEntity cls) {
    throw new UnimplementedError('KernelCommonElements.getRawType');
  }

  @override
  FunctionEntity findConstructor(ClassEntity cls, String name,
      {bool required: true}) {
    throw new UnimplementedError('KernelCommonElements.findConstructor');
  }

  @override
  MemberEntity findClassMember(ClassEntity cls, String name,
      {bool required: true}) {
    throw new UnimplementedError('KernelCommonElements.findClassMember');
  }

  @override
  MemberEntity findLibraryMember(LibraryEntity library, String name,
      {bool required: true}) {
    throw new UnimplementedError('KernelCommonElements.findLibraryMember');
  }

  @override
  ClassEntity findClass(LibraryEntity library, String name,
      {bool required: true}) {
    return worldBuilder.lookupClass(library, name);
  }

  @override
  DynamicType get dynamicType => const DynamicType();

  @override
  ClassEntity get nativeAnnotationClass {
    throw new UnimplementedError('KernelCommonElements.nativeAnnotationClass');
  }

  @override
  ClassEntity get patchAnnotationClass {
    throw new UnimplementedError('KernelCommonElements.patchAnnotationClass');
  }

  @override
  LibraryEntity get typedDataLibrary {
    throw new UnimplementedError('KernelCommonElements.typedDataLibrary');
  }

  @override
  LibraryEntity get mirrorsLibrary {
    throw new UnimplementedError('KernelCommonElements.mirrorsLibrary');
  }

  @override
  LibraryEntity get asyncLibrary {
    throw new UnimplementedError('KernelCommonElements.asyncLibrary');
  }
}

/// Visitor that converts kernel dart types into [DartType].
class DartTypeConverter extends ir.DartTypeVisitor<DartType> {
  final KernelWorldBuilder elementAdapter;
  bool topLevel = true;

  DartTypeConverter(this.elementAdapter);

  DartType convert(ir.DartType type) {
    topLevel = true;
    return type.accept(this);
  }

  /// Visit a inner type.
  DartType visitType(ir.DartType type) {
    topLevel = false;
    return type.accept(this);
  }

  List<DartType> visitTypes(List<ir.DartType> types) {
    topLevel = false;
    return new List.generate(
        types.length, (int index) => types[index].accept(this));
  }

  @override
  DartType visitTypeParameterType(ir.TypeParameterType node) {
    return new TypeVariableType(elementAdapter.getTypeVariable(node.parameter));
  }

  @override
  DartType visitFunctionType(ir.FunctionType node) {
    return new FunctionType(
        visitType(node.returnType),
        visitTypes(node.positionalParameters
            .take(node.requiredParameterCount)
            .toList()),
        visitTypes(node.positionalParameters
            .skip(node.requiredParameterCount)
            .toList()),
        node.namedParameters.map((n) => n.name).toList(),
        node.namedParameters.map((n) => visitType(n.type)).toList());
  }

  @override
  DartType visitInterfaceType(ir.InterfaceType node) {
    ClassEntity cls = elementAdapter.getClass(node.classNode);
    return new InterfaceType(cls, visitTypes(node.typeArguments));
  }

  @override
  DartType visitVoidType(ir.VoidType node) {
    return const VoidType();
  }

  @override
  DartType visitDynamicType(ir.DynamicType node) {
    return const DynamicType();
  }

  @override
  DartType visitInvalidType(ir.InvalidType node) {
    if (topLevel) {
      throw new UnimplementedError(
          "Outermost invalid types not currently supported");
    }
    // Nested invalid types are treated as `dynamic`.
    return const DynamicType();
  }
}
