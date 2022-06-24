// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart2wasm/class_info.dart';
import 'package:dart2wasm/closures.dart';
import 'package:dart2wasm/dispatch_table.dart';
import 'package:dart2wasm/intrinsics.dart';
import 'package:dart2wasm/param_info.dart';
import 'package:dart2wasm/reference_extensions.dart';
import 'package:dart2wasm/translator.dart';
import 'package:dart2wasm/types.dart';

import 'package:kernel/ast.dart';
import 'package:kernel/type_environment.dart';

import 'package:wasm_builder/wasm_builder.dart' as w;

/// Main code generator for member bodies.
///
/// The [generate] method first collects all local functions and function
/// expressions in the body and then generates code for the body. Code for the
/// local functions and function expressions must be generated separately by
/// calling the [generateLambda] method on all lambdas in [closures].
///
/// A new [CodeGenerator] object must be created for each new member or lambda.
///
/// Every visitor method for an expression takes in the Wasm type that it is
/// expected to leave on the stack (or the special [voidMarker] to indicate that
/// it should leave nothing). It returns what it actually left on the stack. The
/// code generation for every expression or subexpression is done via the [wrap]
/// method, which emits appropriate conversion code if the produced type is not
/// a subtype of the expected type.
class CodeGenerator extends ExpressionVisitor1<w.ValueType, w.ValueType>
    implements InitializerVisitor<void>, StatementVisitor<void> {
  final Translator translator;
  final w.DefinedFunction function;
  final Reference reference;
  late final List<w.Local> paramLocals;
  final w.Label? returnLabel;

  late final Intrinsifier intrinsifier;
  late final StaticTypeContext typeContext;
  late final w.Instructions b;

  late final Closures closures;

  final Map<VariableDeclaration, w.Local> locals = {};
  w.Local? thisLocal;
  w.Local? preciseThisLocal;
  w.Local? returnValueLocal;
  final Map<TypeParameter, w.Local> typeLocals = {};
  final List<TryBlockFinalizer> finalizers = [];
  final List<w.Label> tryLabels = [];
  final Map<LabeledStatement, w.Label> labels = {};
  final Map<SwitchCase, w.Label> switchLabels = {};

  /// Maps a switch statement to the information used when doing a backward
  /// jump to one of the cases in the switch statement
  final Map<SwitchStatement, SwitchBackwardJumpInfo> switchBackwardJumpInfos =
      {};

  /// Create a code generator for a member or one of its lambdas.
  ///
  /// The [paramLocals] and [returnLabel] parameters can be used to generate
  /// code for an inlined function by specifying the locals containing the
  /// parameters (instead of the function inputs) and the label to jump to on
  /// return (instead of emitting a `return` instruction).
  CodeGenerator(this.translator, this.function, this.reference,
      {List<w.Local>? paramLocals, this.returnLabel}) {
    this.paramLocals = paramLocals ?? function.locals;
    intrinsifier = Intrinsifier(this);
    typeContext = StaticTypeContext(member, translator.typeEnvironment);
    b = function.body;
  }

  Member get member => reference.asMember;

  w.ValueType get returnType => translator
      .outputOrVoid(returnLabel?.targetTypes ?? function.type.outputs);

  TranslatorOptions get options => translator.options;

  w.ValueType get voidMarker => translator.voidMarker;

  Types get types => translator.types;

  w.ValueType translateType(DartType type) => translator.translateType(type);

  w.Local addLocal(w.ValueType type) {
    return function.addLocal(translator.typeForLocal(type));
  }

  DartType dartTypeOf(Expression exp) {
    return exp.getStaticType(typeContext);
  }

  void unimplemented(
      TreeNode node, Object message, List<w.ValueType> expectedTypes) {
    final text = "Not implemented: $message at ${node.location}";
    print(text);
    b.comment(text);
    b.block(const [], expectedTypes);
    b.unreachable();
    b.end();
  }

  @override
  void defaultInitializer(Initializer node) {
    unimplemented(node, node.runtimeType, const []);
  }

  @override
  w.ValueType defaultExpression(Expression node, w.ValueType expectedType) {
    unimplemented(node, node.runtimeType, [expectedType]);
    return expectedType;
  }

  @override
  void defaultStatement(Statement node) {
    unimplemented(node, node.runtimeType, const []);
  }

  /// Generate code for the member.
  void generate() {
    closures = Closures(this);

    Member member = this.member;

    if (reference.isTearOffReference) {
      return generateTearOffGetter(member as Procedure);
    }

    if (intrinsifier.generateMemberIntrinsic(
        reference, function, paramLocals, returnLabel)) {
      b.end();
      return;
    }

    if (member.isExternal) {
      final text =
          "Unimplemented external member $member at ${member.location}";
      print(text);
      b.comment(text);
      b.unreachable();
      b.end();
      return;
    }

    if (member is Field) {
      if (member.isStatic) {
        return generateStaticFieldInitializer(member);
      } else {
        return generateImplicitAccessor(member);
      }
    }

    return generateBody(member);
  }

  void generateTearOffGetter(Procedure procedure) {
    w.DefinedFunction closureFunction =
        translator.getTearOffFunction(procedure);

    int parameterCount = procedure.function.requiredParameterCount;
    w.DefinedGlobal global = translator.makeFunctionRef(closureFunction);

    ClassInfo info = translator.classInfo[translator.functionClass]!;
    translator.functions.allocateClass(info.classId);

    b.i32_const(info.classId);
    b.i32_const(initialIdentityHash);
    b.local_get(paramLocals[0]);
    b.global_get(global);
    translator.struct_new(b, parameterCount);
    b.end();
  }

  void generateStaticFieldInitializer(Field field) {
    // Static field initializer function
    assert(reference == field.fieldReference);
    closures.findCaptures(field);
    closures.collectContexts(field);
    closures.buildContexts();

    w.Global global = translator.globals.getGlobal(field);
    w.Global? flag = translator.globals.getGlobalInitializedFlag(field);
    wrap(field.initializer!, global.type.type);
    b.global_set(global);
    if (flag != null) {
      b.i32_const(1);
      b.global_set(flag);
    }
    b.global_get(global);
    translator.convertType(
        function, global.type.type, function.type.outputs.single);
    b.end();
  }

  void generateImplicitAccessor(Field field) {
    // Implicit getter or setter
    w.StructType struct = translator.classInfo[field.enclosingClass!]!.struct;
    int fieldIndex = translator.fieldIndex[field]!;
    w.ValueType fieldType = struct.fields[fieldIndex].type.unpacked;

    void getThis() {
      w.Local thisLocal = paramLocals[0];
      w.RefType structType = w.RefType.def(struct, nullable: true);
      b.local_get(thisLocal);
      translator.convertType(function, thisLocal.type, structType);
    }

    if (reference.isImplicitGetter) {
      // Implicit getter
      getThis();
      b.struct_get(struct, fieldIndex);
      translator.convertType(function, fieldType, returnType);
    } else {
      // Implicit setter
      w.Local valueLocal = paramLocals[1];
      getThis();
      b.local_get(valueLocal);
      translator.convertType(function, valueLocal.type, fieldType);
      b.struct_set(struct, fieldIndex);
    }
    b.end();
  }

  void generateBody(Member member) {
    ParameterInfo paramInfo = translator.paramInfoFor(reference);
    bool hasThis = member.isInstanceMember || member is Constructor;
    int typeParameterOffset = hasThis ? 1 : 0;
    int implicitParams = typeParameterOffset + paramInfo.typeParamCount;
    List<VariableDeclaration> positional =
        member.function!.positionalParameters;
    for (int i = 0; i < positional.length; i++) {
      locals[positional[i]] = paramLocals[implicitParams + i];
    }
    List<VariableDeclaration> named = member.function!.namedParameters;
    for (var param in named) {
      locals[param] =
          paramLocals[implicitParams + paramInfo.nameIndex[param.name]!];
    }
    List<TypeParameter> typeParameters = member is Constructor
        ? member.enclosingClass.typeParameters
        : member.function!.typeParameters;
    for (int i = 0; i < typeParameters.length; i++) {
      typeLocals[typeParameters[i]] = paramLocals[typeParameterOffset + i];
    }

    closures.findCaptures(member);

    if (hasThis) {
      Class cls = member.enclosingClass!;
      ClassInfo info = translator.classInfo[cls]!;
      thisLocal = paramLocals[0];
      w.RefType thisType = info.nonNullableType;
      if (translator.needsConversion(paramLocals[0].type, thisType) &&
          !(cls == translator.ffiPointerClass ||
              translator.isFfiCompound(cls))) {
        preciseThisLocal = addLocal(thisType);
        b.local_get(paramLocals[0]);
        translator.ref_cast(b, info);
        b.local_set(preciseThisLocal!);
      } else {
        preciseThisLocal = paramLocals[0];
      }
    }

    closures.collectContexts(member);
    if (member is Constructor) {
      for (Field field in member.enclosingClass.fields) {
        if (field.isInstanceMember && field.initializer != null) {
          closures.collectContexts(field.initializer!,
              container: member.function);
        }
      }
    }
    closures.buildContexts();

    allocateContext(member.function!);
    captureParameters();

    if (member is Constructor) {
      Class cls = member.enclosingClass;
      ClassInfo info = translator.classInfo[cls]!;
      for (TypeParameter typeParam in cls.typeParameters) {
        b.local_get(thisLocal!);
        b.local_get(typeLocals[typeParam]!);
        b.struct_set(info.struct, translator.typeParameterIndex[typeParam]!);
      }
      for (Field field in cls.fields) {
        if (field.isInstanceMember && field.initializer != null) {
          int fieldIndex = translator.fieldIndex[field]!;
          b.local_get(thisLocal!);
          wrap(
              field.initializer!, info.struct.fields[fieldIndex].type.unpacked);
          b.struct_set(info.struct, fieldIndex);
        }
      }
      for (Initializer initializer in member.initializers) {
        initializer.accept(this);
      }
    }

    member.function!.body?.accept(this);
    _implicitReturn();
    b.end();
  }

  /// Generate code for the body of a lambda.
  void generateLambda(Lambda lambda, Closures closures) {
    this.closures = closures;

    final int implicitParams = 1;
    List<VariableDeclaration> positional =
        lambda.functionNode.positionalParameters;
    for (int i = 0; i < positional.length; i++) {
      locals[positional[i]] = paramLocals[implicitParams + i];
    }

    Context? context = closures.contexts[lambda.functionNode]?.parent;
    if (context != null) {
      b.local_get(paramLocals[0]);
      translator.ref_cast(b, context.struct);
      while (true) {
        w.Local contextLocal =
            addLocal(w.RefType.def(context!.struct, nullable: false));
        context.currentLocal = contextLocal;
        if (context.parent != null || context.containsThis) {
          b.local_tee(contextLocal);
        } else {
          b.local_set(contextLocal);
        }
        if (context.parent == null) break;

        b.struct_get(context.struct, context.parentFieldIndex);
        if (options.localNullability) {
          b.ref_as_non_null();
        }
        context = context.parent!;
      }
      if (context.containsThis) {
        thisLocal = addLocal(
            context.struct.fields[context.thisFieldIndex].type.unpacked);
        preciseThisLocal = thisLocal;
        b.struct_get(context.struct, context.thisFieldIndex);
        b.local_set(thisLocal!);
      }
    }
    allocateContext(lambda.functionNode);
    captureParameters();

    lambda.functionNode.body!.accept(this);
    _implicitReturn();
    b.end();
  }

  void _implicitReturn() {
    if (function.type.outputs.length > 0) {
      w.ValueType returnType = function.type.outputs[0];
      if (returnType is w.RefType && returnType.nullable) {
        // Dart body may have an implicit return null.
        b.ref_null(returnType.heapType);
      } else {
        // This point is unreachable, but the Wasm validator still expects the
        // stack to contain a value matching the Wasm function return type.
        b.block(const [], function.type.outputs);
        b.comment("Unreachable implicit return");
        b.unreachable();
        b.end();
      }
    }
  }

  void allocateContext(TreeNode node) {
    Context? context = closures.contexts[node];
    if (context != null && !context.isEmpty) {
      w.Local contextLocal =
          addLocal(w.RefType.def(context.struct, nullable: false));
      context.currentLocal = contextLocal;
      translator.struct_new_default(b, context.struct);
      b.local_set(contextLocal);
      if (context.containsThis) {
        b.local_get(contextLocal);
        b.local_get(preciseThisLocal!);
        b.struct_set(context.struct, context.thisFieldIndex);
      }
      if (context.parent != null) {
        w.Local parentLocal = context.parent!.currentLocal;
        b.local_get(contextLocal);
        b.local_get(parentLocal);
        b.struct_set(context.struct, context.parentFieldIndex);
      }
    }
  }

  void captureParameters() {
    locals.forEach((variable, local) {
      Capture? capture = closures.captures[variable];
      if (capture != null) {
        b.local_get(capture.context.currentLocal);
        b.local_get(local);
        translator.convertType(function, local.type, capture.type);
        b.struct_set(capture.context.struct, capture.fieldIndex);
      }
    });
    typeLocals.forEach((parameter, local) {
      Capture? capture = closures.captures[parameter];
      if (capture != null) {
        b.local_get(capture.context.currentLocal);
        b.local_get(local);
        translator.convertType(function, local.type, capture.type);
        b.struct_set(capture.context.struct, capture.fieldIndex);
      }
    });
  }

  /// Helper function to throw a Wasm ref downcast error.
  void throwWasmRefError(String expected) {
    wrap(
        StringLiteral(expected),
        translator
            .translateType(translator.coreTypes.stringNonNullableRawType));
    call(translator.stackTraceCurrent.reference);
    call(translator.throwWasmRefError.reference);
    b.unreachable();
  }

  /// Generates code for an expression plus conversion code to convert the
  /// result to the expected type if needed. All expression code generation goes
  /// through this method.
  w.ValueType wrap(Expression node, w.ValueType expectedType) {
    w.ValueType resultType = node.accept1(this, expectedType);
    translator.convertType(function, resultType, expectedType);
    return expectedType;
  }

  w.ValueType call(Reference target) {
    w.BaseFunction targetFunction = translator.functions.getFunction(target);
    if (translator.shouldInline(target)) {
      List<w.Local> inlinedLocals =
          targetFunction.type.inputs.map((t) => addLocal(t)).toList();
      for (w.Local local in inlinedLocals.reversed) {
        b.local_set(local);
      }
      w.Label block = b.block(const [], targetFunction.type.outputs);
      b.comment("Inlined ${target.asMember}");
      CodeGenerator(translator, function, target,
              paramLocals: inlinedLocals, returnLabel: block)
          .generate();
    } else {
      String access =
          target.isGetter ? "get" : (target.isSetter ? "set" : "call");
      b.comment("Direct $access of '${target.asMember}'");
      b.call(targetFunction);
    }
    return translator.outputOrVoid(targetFunction.type.outputs);
  }

  @override
  void visitInvalidInitializer(InvalidInitializer node) {}

  @override
  void visitAssertInitializer(AssertInitializer node) {}

  @override
  void visitLocalInitializer(LocalInitializer node) {
    node.variable.accept(this);
  }

  @override
  void visitFieldInitializer(FieldInitializer node) {
    Class cls = (node.parent as Constructor).enclosingClass;
    w.StructType struct = translator.classInfo[cls]!.struct;
    int fieldIndex = translator.fieldIndex[node.field]!;

    b.local_get(thisLocal!);
    wrap(node.value, struct.fields[fieldIndex].type.unpacked);
    b.struct_set(struct, fieldIndex);
  }

  @override
  void visitRedirectingInitializer(RedirectingInitializer node) {
    Class cls = (node.parent as Constructor).enclosingClass;
    b.local_get(thisLocal!);
    if (options.parameterNullability && thisLocal!.type.nullable) {
      b.ref_as_non_null();
    }
    for (TypeParameter typeParam in cls.typeParameters) {
      types.makeType(
          this, TypeParameterType(typeParam, Nullability.nonNullable));
    }
    _visitArguments(node.arguments, node.targetReference, 1);
    call(node.targetReference);
  }

  @override
  void visitSuperInitializer(SuperInitializer node) {
    Supertype? supertype =
        (node.parent as Constructor).enclosingClass.supertype;
    if (supertype?.classNode.superclass == null) {
      return;
    }
    b.local_get(thisLocal!);
    if (options.parameterNullability && thisLocal!.type.nullable) {
      b.ref_as_non_null();
    }
    for (DartType typeArg in supertype!.typeArguments) {
      types.makeType(this, typeArg);
    }
    _visitArguments(node.arguments, node.targetReference,
        1 + supertype.typeArguments.length);
    call(node.targetReference);
  }

  @override
  void visitBlock(Block node) {
    for (Statement statement in node.statements) {
      statement.accept(this);
    }
  }

  @override
  void visitLabeledStatement(LabeledStatement node) {
    w.Label label = b.block();
    labels[node] = label;
    node.body.accept(this);
    labels.remove(node);
    b.end();
  }

  @override
  void visitBreakStatement(BreakStatement node) {
    b.br(labels[node.target]!);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.type is VoidType) {
      if (node.initializer != null) {
        wrap(node.initializer!, voidMarker);
      }
      return;
    }
    w.ValueType type = translateType(node.type);
    w.Local? local;
    Capture? capture = closures.captures[node];
    if (capture == null || !capture.written) {
      local = addLocal(type);
      locals[node] = local;
    }
    if (node.initializer != null) {
      if (capture != null) {
        w.ValueType expectedType = capture.written ? capture.type : local!.type;
        b.local_get(capture.context.currentLocal);
        wrap(node.initializer!, expectedType);
        if (!capture.written) {
          b.local_tee(local!);
        }
        b.struct_set(capture.context.struct, capture.fieldIndex);
      } else {
        wrap(node.initializer!, local!.type);
        b.local_set(local);
      }
    } else if (local != null && !local.type.defaultable) {
      // Uninitialized variable
      translator.globals.instantiateDummyValue(b, local.type);
      b.local_set(local);
    }
  }

  @override
  void visitEmptyStatement(EmptyStatement node) {}

  @override
  void visitAssertStatement(AssertStatement node) {}

  @override
  void visitAssertBlock(AssertBlock node) {}

  @override
  void visitTryCatch(TryCatch node) {
    // It is not valid dart to have a try without a catch.
    assert(node.catches.isNotEmpty);

    // We lower a [TryCatch] to a wasm try block. If there are any [Catch]
    // nodes, we generate a single wasm catch instruction, and dispatch at
    // runtime based on the type of the caught exception.
    w.Label try_ = b.try_();
    node.body.accept(this);
    b.br(try_);

    // Insert a catch instruction which will catch any thrown Dart
    // exceptions.
    // Note: We must wait to add the try block to the [tryLabels] stack until
    // after we have visited the body of the try. This is to handle the case of
    // a rethrow nested within a try nested within a catch, that is we need the
    // rethrow to target the last try block with a catch.
    tryLabels.add(try_);
    b.catch_(translator.exceptionTag);

    // Stash the original exception in a local so we can push it back onto the
    // stack after each type test. Also, store the stack trace in a local.
    w.RefType stackTrace = translator.stackTraceInfo.nonNullableType;
    w.Local thrownStackTrace = addLocal(stackTrace);
    b.local_set(thrownStackTrace);

    w.RefType exception = translator.topInfo.nonNullableType;
    w.Local thrownException = addLocal(exception);
    b.local_set(thrownException);

    // For each catch node:
    //   1) Create a block for the catch.
    //   2) Push the caught exception onto the stack.
    //   3) Add a type test based on the guard of the catch.
    //   4) If the test fails, we jump to the next catch. Otherwise, we
    //      execute the body of the catch.
    for (Catch catch_ in node.catches) {
      w.Label catchBlock = b.block();
      DartType guard = catch_.guard;

      // Only emit the type test if the guard is not [Object].
      if (guard != translator.coreTypes.objectNonNullableRawType) {
        b.local_get(thrownException);
        types.emitTypeTest(
            this, guard, translator.coreTypes.objectNonNullableRawType, node);
        b.i32_eqz();
        b.br_if(catchBlock);
      }

      // If there is an exception declaration, create a local corresponding to
      // the catch's exception [VariableDeclaration] node.
      VariableDeclaration? exceptionDeclaration = catch_.exception;
      if (exceptionDeclaration != null) {
        w.Local guardedException = addLocal(exception);
        locals[exceptionDeclaration] = guardedException;
        b.local_get(thrownException);
        b.local_set(guardedException);
      }

      // If there is a stack trace declaration, then create a local
      // corresponding to the catch's stack trace [VariableDeclaration] node.
      VariableDeclaration? stackTraceDeclaration = catch_.stackTrace;
      if (stackTraceDeclaration != null) {
        w.Local guardedStackTrace = addLocal(stackTrace);
        locals[stackTraceDeclaration] = guardedStackTrace;
        b.local_get(thrownStackTrace);
        b.local_set(guardedStackTrace);
      }
      catch_.body.accept(this);

      // Jump out of the try entirely if we enter any catch block.
      b.br(try_);
      b.end(); // end catchBlock.
    }

    // We insert a rethrow just before the end of the try block to handle the
    // case where none of the catch blocks catch the type of the thrown
    // exception.
    b.rethrow_(try_);
    tryLabels.removeLast();
    b.end(); // end try_.
  }

  @override
  void visitTryFinally(TryFinally node) {
    // We lower a [TryFinally] to three nested blocks, and we emit the finalizer
    // up to three times. Once in a catch, to handle the case where the try
    // throws. Once outside of the catch, to handle the case where the try does
    // not throw. Finally, if there is a return within the try block, then we
    // emit the finalizer one more time along with logic to continue walking up
    // the stack.
    w.Label tryFinallyBlock = b.block();
    w.Label finalizerBlock = b.block();
    finalizers.add(TryBlockFinalizer(finalizerBlock));
    w.Label tryBlock = b.try_();
    node.body.accept(this);
    bool mustHandleReturn = finalizers.removeLast().mustHandleReturn;
    b.br(tryBlock);
    b.catch_(translator.exceptionTag);
    node.finalizer.accept(this);
    b.rethrow_(tryBlock);
    b.end(); // end tryBlock.
    node.finalizer.accept(this);
    b.br(tryFinallyBlock);
    b.end(); // end finalizerBlock.
    if (mustHandleReturn) {
      node.finalizer.accept(this);
      if (finalizers.isNotEmpty) {
        b.br(finalizers.last.label);
      } else {
        if (returnValueLocal != null) {
          b.local_get(returnValueLocal!);
          translator.convertType(function, returnValueLocal!.type, returnType);
        }
        _returnFromFunction();
      }
    }
    b.end(); // end tryFinallyBlock.
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    wrap(node.expression, voidMarker);
  }

  bool _hasLogicalOperator(Expression condition) {
    while (condition is Not) condition = condition.operand;
    return condition is LogicalExpression;
  }

  void _branchIf(Expression? condition, w.Label target,
      {required bool negated}) {
    if (condition == null) {
      if (!negated) b.br(target);
      return;
    }
    while (condition is Not) {
      negated = !negated;
      condition = condition.operand;
    }
    if (condition is LogicalExpression) {
      bool isConjunctive =
          (condition.operatorEnum == LogicalExpressionOperator.AND) ^ negated;
      if (isConjunctive) {
        w.Label conditionBlock = b.block();
        _branchIf(condition.left, conditionBlock, negated: !negated);
        _branchIf(condition.right, target, negated: negated);
        b.end();
      } else {
        _branchIf(condition.left, target, negated: negated);
        _branchIf(condition.right, target, negated: negated);
      }
    } else {
      wrap(condition!, w.NumType.i32);
      if (negated) {
        b.i32_eqz();
      }
      b.br_if(target);
    }
  }

  void _conditional(Expression condition, void then(), void otherwise()?,
      List<w.ValueType> result) {
    if (!_hasLogicalOperator(condition)) {
      // Simple condition
      wrap(condition, w.NumType.i32);
      b.if_(const [], result);
      then();
      if (otherwise != null) {
        b.else_();
        otherwise();
      }
      b.end();
    } else {
      // Complex condition
      w.Label ifBlock = b.block(const [], result);
      if (otherwise != null) {
        w.Label elseBlock = b.block();
        _branchIf(condition, elseBlock, negated: true);
        then();
        b.br(ifBlock);
        b.end();
        otherwise();
      } else {
        _branchIf(condition, ifBlock, negated: true);
        then();
      }
      b.end();
    }
  }

  @override
  void visitIfStatement(IfStatement node) {
    _conditional(
        node.condition,
        () => node.then.accept(this),
        node.otherwise != null ? () => node.otherwise!.accept(this) : null,
        const []);
  }

  @override
  void visitDoStatement(DoStatement node) {
    w.Label loop = b.loop();
    allocateContext(node);
    node.body.accept(this);
    _branchIf(node.condition, loop, negated: false);
    b.end();
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    w.Label block = b.block();
    w.Label loop = b.loop();
    _branchIf(node.condition, block, negated: true);
    allocateContext(node);
    node.body.accept(this);
    b.br(loop);
    b.end();
    b.end();
  }

  @override
  void visitForStatement(ForStatement node) {
    Context? context = closures.contexts[node];
    allocateContext(node);
    for (VariableDeclaration variable in node.variables) {
      variable.accept(this);
    }
    w.Label block = b.block();
    w.Label loop = b.loop();
    _branchIf(node.condition, block, negated: true);
    node.body.accept(this);
    if (node.variables.any((v) => closures.captures.containsKey(v))) {
      w.Local oldContext = context!.currentLocal;
      allocateContext(node);
      w.Local newContext = context.currentLocal;
      for (VariableDeclaration variable in node.variables) {
        Capture? capture = closures.captures[variable];
        if (capture != null) {
          b.local_get(oldContext);
          b.struct_get(context.struct, capture.fieldIndex);
          b.local_get(newContext);
          b.struct_set(context.struct, capture.fieldIndex);
        }
      }
    } else {
      allocateContext(node);
    }
    for (Expression update in node.updates) {
      wrap(update, voidMarker);
    }
    b.br(loop);
    b.end();
    b.end();
  }

  @override
  void visitForInStatement(ForInStatement node) {
    throw "ForInStatement should have been desugared: $node";
  }

  /// Handle the return from this function, either by jumping to [returnLabel]
  /// in the case this function was inlined or just inserting a return
  /// instruction.
  void _returnFromFunction() {
    if (returnLabel != null) {
      b.br(returnLabel!);
    } else {
      b.return_();
    }
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    Expression? expression = node.expression;
    if (expression != null) {
      wrap(expression, returnType);
    } else {
      translator.convertType(function, voidMarker, returnType);
    }

    // If we are wrapped in a [TryFinally] node then we have to run finalizers
    // as the stack unwinds. When we get to the top of the finalizer stack, we
    // will handle the return using [returnValueLocal] if this function returns
    // a value.
    if (finalizers.isNotEmpty) {
      for (TryBlockFinalizer finalizer in finalizers) {
        finalizer.mustHandleReturn = true;
      }
      if (returnType != voidMarker) {
        returnValueLocal ??= addLocal(returnType);
        b.local_set(returnValueLocal!);
      }
      b.br(finalizers.last.label);
    } else {
      _returnFromFunction();
    }
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    bool check<L extends Expression, C extends Constant>() =>
        node.cases.expand((c) => c.expressions).every((e) =>
            e is L ||
            e is NullLiteral ||
            e is ConstantExpression &&
                (e.constant is C || e.constant is NullConstant));

    // Identify kind of switch. One of `nullableType` or `nonNullableType` will
    // be the type for Wasm local that holds the switch value.
    w.ValueType nullableType;
    w.ValueType nonNullableType;
    void Function() compare;
    if (check<BoolLiteral, BoolConstant>()) {
      // bool switch
      nonNullableType = w.NumType.i32;
      nullableType =
          translator.classInfo[translator.boxedBoolClass]!.nullableType;
      compare = () => b.i32_eq();
    } else if (check<IntLiteral, IntConstant>()) {
      // int switch
      nonNullableType = w.NumType.i64;
      nullableType =
          translator.classInfo[translator.boxedIntClass]!.nullableType;
      compare = () => b.i64_eq();
    } else if (check<StringLiteral, StringConstant>()) {
      // String switch
      nonNullableType =
          translator.classInfo[translator.stringBaseClass]!.nonNullableType;
      nullableType = nonNullableType.withNullability(true);
      compare = () => call(translator.stringEquals.reference);
    } else {
      // Object switch
      assert(check<InvalidExpression, InstanceConstant>());
      nonNullableType = w.RefType.eq(nullable: false);
      nullableType = w.RefType.eq(nullable: true);
      compare = () => b.ref_eq();
    }

    bool isNullable = dartTypeOf(node.expression).isPotentiallyNullable;

    // When the type is nullable we use two variables: one for the nullable
    // value, one after the null check, with non-nullable type.
    w.Local switchValueNonNullableLocal = addLocal(nonNullableType);
    w.Local? switchValueNullableLocal =
        isNullable ? addLocal(nullableType) : null;

    // Initialize switch value local
    wrap(node.expression, isNullable ? nullableType : nonNullableType);
    b.local_set(
        isNullable ? switchValueNullableLocal! : switchValueNonNullableLocal);

    // Special cases
    SwitchCase? defaultCase = node.cases
        .cast<SwitchCase?>()
        .firstWhere((c) => c!.isDefault, orElse: () => null);

    SwitchCase? nullCase = node.cases.cast<SwitchCase?>().firstWhere(
        (c) => c!.expressions.any((e) =>
            e is NullLiteral ||
            e is ConstantExpression && e.constant is NullConstant),
        orElse: () => null);

    // Create `loop` for backward jumps
    w.Label loopLabel = b.loop();

    // Set `switchValueLocal` for backward jumps
    w.Local switchValueLocal =
        isNullable ? switchValueNullableLocal! : switchValueNonNullableLocal;

    // Add backward jump info
    switchBackwardJumpInfos[node] =
        SwitchBackwardJumpInfo(switchValueLocal, loopLabel);

    // Set up blocks, in reverse order of cases so they end in forward order
    w.Label doneLabel = b.block();
    for (SwitchCase c in node.cases.reversed) {
      switchLabels[c] = b.block();
    }

    // Compute value and handle null
    if (isNullable) {
      w.Label nullLabel = nullCase != null
          ? switchLabels[nullCase]!
          : defaultCase != null
              ? switchLabels[defaultCase]!
              : doneLabel;
      b.local_get(switchValueNullableLocal!);
      b.br_on_null(nullLabel);
      translator.convertType(
          function, nullableType.withNullability(false), nonNullableType);
      b.local_set(switchValueNonNullableLocal);
    }

    // Compare against all case values
    for (SwitchCase c in node.cases) {
      for (Expression exp in c.expressions) {
        if (exp is NullLiteral ||
            exp is ConstantExpression && exp.constant is NullConstant) {
          // Null already checked, skip
        } else {
          wrap(exp, nonNullableType);
          b.local_get(switchValueNonNullableLocal);
          translator.convertType(
              function, switchValueNonNullableLocal.type, nonNullableType);
          compare();
          b.br_if(switchLabels[c]!);
        }
      }
    }

    // No explicit cases matched
    if (node.isExplicitlyExhaustive) {
      b.unreachable();
    } else {
      w.Label defaultLabel =
          defaultCase != null ? switchLabels[defaultCase]! : doneLabel;
      b.br(defaultLabel);
    }

    // Emit case bodies
    for (SwitchCase c in node.cases) {
      b.end();
      // Remove backward jump target from forward jump labels
      switchLabels.remove(c);

      // Create a `loop` in default case to allow backward jumps to it
      if (c.isDefault) {
        switchBackwardJumpInfos[node]!.defaultLoopLabel = b.loop();
      }

      c.body.accept(this);

      if (c.isDefault) {
        b.end(); // defaultLoopLabel
      }

      b.br(doneLabel);
    }
    b.end(); // doneLabel
    b.end(); // loopLabel

    // Remove backward jump info
    final removed = switchBackwardJumpInfos.remove(node);
    assert(removed != null);
  }

  @override
  void visitContinueSwitchStatement(ContinueSwitchStatement node) {
    w.Label? label = switchLabels[node.target];
    if (label != null) {
      b.br(label);
    } else {
      // Backward jump. Find the case literal in jump target, set the switched
      // values to the jump target's value, and loop.
      final SwitchCase targetSwitchCase = node.target;
      final SwitchStatement targetSwitch =
          targetSwitchCase.parent! as SwitchStatement;
      final SwitchBackwardJumpInfo targetInfo =
          switchBackwardJumpInfos[targetSwitch]!;
      if (targetSwitchCase.expressions.isEmpty) {
        // Default case
        assert(targetSwitchCase.isDefault);
        b.br(targetInfo.defaultLoopLabel!);
        return;
      }
      final Expression targetValue =
          targetSwitchCase.expressions[0]; // pick any of the values
      wrap(targetValue, targetInfo.switchValueLocal.type);
      b.local_set(targetInfo.switchValueLocal);
      b.br(targetInfo.loopLabel);
    }
  }

  @override
  void visitYieldStatement(YieldStatement node) => defaultStatement(node);

  @override
  w.ValueType visitBlockExpression(
      BlockExpression node, w.ValueType expectedType) {
    node.body.accept(this);
    return wrap(node.value, expectedType);
  }

  @override
  w.ValueType visitLet(Let node, w.ValueType expectedType) {
    node.variable.accept(this);
    return wrap(node.body, expectedType);
  }

  @override
  w.ValueType visitThisExpression(
      ThisExpression node, w.ValueType expectedType) {
    return visitThis(expectedType);
  }

  w.ValueType visitThis(w.ValueType expectedType) {
    w.ValueType thisType = thisLocal!.type.withNullability(false);
    w.ValueType preciseThisType = preciseThisLocal!.type.withNullability(false);
    if (!thisType.isSubtypeOf(expectedType) &&
        preciseThisType.isSubtypeOf(expectedType)) {
      b.local_get(preciseThisLocal!);
      return preciseThisLocal!.type;
    } else {
      b.local_get(thisLocal!);
      return thisLocal!.type;
    }
  }

  @override
  w.ValueType visitConstructorInvocation(
      ConstructorInvocation node, w.ValueType expectedType) {
    w.ValueType? intrinsicResult =
        intrinsifier.generateConstructorIntrinsic(node);
    if (intrinsicResult != null) return intrinsicResult;

    ClassInfo info = translator.classInfo[node.target.enclosingClass]!;
    translator.functions.allocateClass(info.classId);
    w.Local temp = addLocal(info.nonNullableType);
    translator.struct_new_default(b, info);
    b.local_tee(temp);
    b.local_get(temp);
    b.i32_const(info.classId);
    b.struct_set(info.struct, FieldIndex.classId);
    if (options.parameterNullability && temp.type.nullable) {
      b.ref_as_non_null();
    }
    _visitArguments(node.arguments, node.targetReference, 1);
    call(node.targetReference);
    if (expectedType != voidMarker) {
      b.local_get(temp);
      return temp.type;
    } else {
      return voidMarker;
    }
  }

  @override
  w.ValueType visitStaticInvocation(
      StaticInvocation node, w.ValueType expectedType) {
    w.ValueType? intrinsicResult = intrinsifier.generateStaticIntrinsic(node);
    if (intrinsicResult != null) return intrinsicResult;

    _visitArguments(node.arguments, node.targetReference, 0);
    return call(node.targetReference);
  }

  Member _lookupSuperTarget(Member interfaceTarget, {required bool setter}) {
    return translator.hierarchy.getDispatchTarget(
        member.enclosingClass!.superclass!, interfaceTarget.name,
        setter: setter)!;
  }

  @override
  w.ValueType visitSuperMethodInvocation(
      SuperMethodInvocation node, w.ValueType expectedType) {
    Reference target =
        _lookupSuperTarget(node.interfaceTarget, setter: false).reference;
    w.BaseFunction targetFunction = translator.functions.getFunction(target);
    w.ValueType receiverType = targetFunction.type.inputs.first;
    w.ValueType thisType = visitThis(receiverType);
    translator.convertType(function, thisType, receiverType);
    _visitArguments(node.arguments, target, 1);
    return call(target);
  }

  @override
  w.ValueType visitInstanceInvocation(
      InstanceInvocation node, w.ValueType expectedType) {
    w.ValueType? intrinsicResult = intrinsifier.generateInstanceIntrinsic(node);
    if (intrinsicResult != null) return intrinsicResult;

    Procedure target = node.interfaceTarget;
    if (node.kind == InstanceAccessKind.Object) {
      switch (target.name.text) {
        case "toString":
          late w.Label done;
          w.ValueType resultType = _virtualCall(node, target, (signature) {
            done = b.block(const [], signature.outputs);
            w.Label nullString = b.block();
            wrap(node.receiver, translator.topInfo.nullableType);
            b.br_on_null(nullString);
          }, (_) {
            _visitArguments(node.arguments, node.interfaceTargetReference, 1);
          }, getter: false, setter: false);
          b.br(done);
          b.end();
          wrap(StringLiteral("null"), resultType);
          b.end();
          return resultType;
        default:
          unimplemented(node, "Nullable invocation of ${target.name.text}",
              [if (expectedType != voidMarker) expectedType]);
          return expectedType;
      }
    }
    Member? singleTarget = translator.singleTarget(node);
    if (singleTarget != null) {
      w.BaseFunction targetFunction =
          translator.functions.getFunction(singleTarget.reference);
      wrap(node.receiver, targetFunction.type.inputs.first);
      _visitArguments(node.arguments, node.interfaceTargetReference, 1);
      return call(singleTarget.reference);
    }
    return _virtualCall(node, target,
        (signature) => wrap(node.receiver, signature.inputs.first), (_) {
      _visitArguments(node.arguments, node.interfaceTargetReference, 1);
    }, getter: false, setter: false);
  }

  @override
  w.ValueType visitDynamicInvocation(
      DynamicInvocation node, w.ValueType expectedType) {
    if (node.name.text != "call") {
      unimplemented(node, "Dynamic invocation of ${node.name.text}",
          [if (expectedType != voidMarker) expectedType]);
      return expectedType;
    }
    return _functionCall(
        node.arguments.positional.length, node.receiver, node.arguments);
  }

  @override
  w.ValueType visitEqualsCall(EqualsCall node, w.ValueType expectedType) {
    w.ValueType? intrinsicResult = intrinsifier.generateEqualsIntrinsic(node);
    if (intrinsicResult != null) return intrinsicResult;

    Member? singleTarget = translator.singleTarget(node);
    if (singleTarget == translator.coreTypes.objectEquals) {
      // Plain reference comparison
      wrap(node.left, w.RefType.eq(nullable: true));
      wrap(node.right, w.RefType.eq(nullable: true));
      b.ref_eq();
    } else {
      // Check operands for null, then call implementation
      bool leftNullable = dartTypeOf(node.left).isPotentiallyNullable;
      bool rightNullable = dartTypeOf(node.right).isPotentiallyNullable;
      w.RefType leftType = translator.topInfo.typeWithNullability(leftNullable);
      w.RefType rightType =
          translator.topInfo.typeWithNullability(rightNullable);
      w.Local leftLocal = addLocal(leftType);
      w.Local rightLocal = addLocal(rightType);
      w.Label? operandNull;
      w.Label? done;
      if (leftNullable || rightNullable) {
        done = b.block(const [], const [w.NumType.i32]);
        operandNull = b.block();
      }
      wrap(node.left, leftLocal.type);
      b.local_set(leftLocal);
      wrap(node.right, rightLocal.type);
      if (rightNullable) {
        b.local_tee(rightLocal);
        b.br_on_null(operandNull!);
        b.drop();
      } else {
        b.local_set(rightLocal);
      }

      void left([_]) {
        b.local_get(leftLocal);
        if (leftNullable) {
          b.br_on_null(operandNull!);
        } else if (leftLocal.type.nullable) {
          b.ref_as_non_null();
        }
      }

      void right([_]) {
        b.local_get(rightLocal);
        if (rightLocal.type.nullable) {
          b.ref_as_non_null();
        }
      }

      if (singleTarget != null) {
        left();
        right();
        call(singleTarget.reference);
      } else {
        _virtualCall(node, node.interfaceTarget, left, right,
            getter: false, setter: false);
      }
      if (leftNullable || rightNullable) {
        b.br(done!);
        b.end(); // operandNull
        if (leftNullable && rightNullable) {
          // Both sides nullable - compare references
          b.local_get(leftLocal);
          b.local_get(rightLocal);
          b.ref_eq();
        } else {
          // Only one side nullable - not equal if one is null
          b.i32_const(0);
        }
        b.end(); // done
      }
    }
    return w.NumType.i32;
  }

  @override
  w.ValueType visitEqualsNull(EqualsNull node, w.ValueType expectedType) {
    wrap(node.expression, const w.RefType.any());
    b.ref_is_null();
    return w.NumType.i32;
  }

  w.ValueType _virtualCall(
      TreeNode node,
      Member interfaceTarget,
      void pushReceiver(w.FunctionType signature),
      void pushArguments(w.FunctionType signature),
      {required bool getter,
      required bool setter}) {
    SelectorInfo selector = translator.dispatchTable.selectorForTarget(
        interfaceTarget.referenceAs(getter: getter, setter: setter));
    assert(selector.name == interfaceTarget.name.text);

    pushReceiver(selector.signature);

    int? offset = selector.offset;
    if (offset == null) {
      // Singular target or unreachable call
      assert(selector.targetCount <= 1);
      if (selector.targetCount == 1) {
        pushArguments(selector.signature);
        return call(selector.singularTarget!);
      } else {
        b.comment("Virtual call of ${selector.name} with no targets"
            " at ${node.location}");
        b.drop();
        b.block(const [], selector.signature.outputs);
        b.unreachable();
        b.end();
        return translator.outputOrVoid(selector.signature.outputs);
      }
    }

    // Receiver is already on stack.
    w.Local receiverVar = addLocal(selector.signature.inputs.first);
    b.local_tee(receiverVar);
    if (options.parameterNullability && receiverVar.type.nullable) {
      b.ref_as_non_null();
    }
    pushArguments(selector.signature);

    if (options.polymorphicSpecialization) {
      _polymorphicSpecialization(selector, receiverVar);
    } else {
      String access = getter ? "get" : (setter ? "set" : "call");
      b.comment("Instance $access of '${selector.name}'");
      b.local_get(receiverVar);
      b.struct_get(translator.topInfo.struct, FieldIndex.classId);
      if (offset != 0) {
        b.i32_const(offset);
        b.i32_add();
      }
      b.call_indirect(selector.signature);

      translator.functions.activateSelector(selector);
    }

    return translator.outputOrVoid(selector.signature.outputs);
  }

  void _polymorphicSpecialization(SelectorInfo selector, w.Local receiver) {
    Map<int, Reference> implementations = Map.from(selector.targets);
    implementations.removeWhere((id, target) => target.asMember.isAbstract);

    w.Local idVar = addLocal(w.NumType.i32);
    b.local_get(receiver);
    b.struct_get(translator.topInfo.struct, FieldIndex.classId);
    b.local_set(idVar);

    w.Label block =
        b.block(selector.signature.inputs, selector.signature.outputs);
    calls:
    while (Set.from(implementations.values).length > 1) {
      for (int id in implementations.keys) {
        Reference target = implementations[id]!;
        if (implementations.values.where((t) => t == target).length == 1) {
          // Single class id implements method.
          b.local_get(idVar);
          b.i32_const(id);
          b.i32_eq();
          b.if_(selector.signature.inputs, selector.signature.inputs);
          call(target);
          b.br(block);
          b.end();
          implementations.remove(id);
          continue calls;
        }
      }
      // Find class id that separates remaining classes in two.
      List<int> sorted = implementations.keys.toList()..sort();
      int pivotId = sorted.firstWhere(
          (id) => implementations[id] != implementations[sorted.first]);
      // Fail compilation if no such id exists.
      assert(sorted.lastWhere(
              (id) => implementations[id] != implementations[pivotId]) ==
          pivotId - 1);
      Reference target = implementations[sorted.first]!;
      b.local_get(idVar);
      b.i32_const(pivotId);
      b.i32_lt_u();
      b.if_(selector.signature.inputs, selector.signature.inputs);
      call(target);
      b.br(block);
      b.end();
      for (int id in sorted) {
        if (id == pivotId) break;
        implementations.remove(id);
      }
      continue calls;
    }
    // Call remaining implementation.
    Reference target = implementations.values.first;
    call(target);
    b.end();
  }

  @override
  w.ValueType visitVariableGet(VariableGet node, w.ValueType expectedType) {
    w.Local? local = locals[node.variable];
    Capture? capture = closures.captures[node.variable];
    if (capture != null) {
      if (!capture.written && local != null) {
        b.local_get(local);
        return local.type;
      } else {
        b.local_get(capture.context.currentLocal);
        b.struct_get(capture.context.struct, capture.fieldIndex);
        return capture.type;
      }
    } else {
      if (local == null) {
        throw "Read of undefined variable ${node.variable}";
      }
      b.local_get(local);
      return local.type;
    }
  }

  @override
  w.ValueType visitVariableSet(VariableSet node, w.ValueType expectedType) {
    w.Local? local = locals[node.variable];
    Capture? capture = closures.captures[node.variable];
    bool preserved = expectedType != voidMarker;
    if (capture != null) {
      assert(capture.written);
      b.local_get(capture.context.currentLocal);
      wrap(node.value, capture.type);
      if (preserved) {
        w.Local temp = addLocal(translateType(node.variable.type));
        b.local_tee(temp);
        b.struct_set(capture.context.struct, capture.fieldIndex);
        b.local_get(temp);
        return temp.type;
      } else {
        b.struct_set(capture.context.struct, capture.fieldIndex);
        return voidMarker;
      }
    } else {
      if (local == null) {
        throw "Write of undefined variable ${node.variable}";
      }
      wrap(node.value, local.type);
      if (preserved) {
        b.local_tee(local);
        return local.type;
      } else {
        b.local_set(local);
        return voidMarker;
      }
    }
  }

  @override
  w.ValueType visitStaticGet(StaticGet node, w.ValueType expectedType) {
    w.ValueType? intrinsicResult =
        intrinsifier.generateStaticGetterIntrinsic(node);
    if (intrinsicResult != null) return intrinsicResult;

    Member target = node.target;
    if (target is Field) {
      return translator.globals.readGlobal(b, target);
    } else {
      return call(target.reference);
    }
  }

  @override
  w.ValueType visitStaticTearOff(StaticTearOff node, w.ValueType expectedType) {
    translator.constants.instantiateConstant(
        function, b, StaticTearOffConstant(node.target), expectedType);
    return expectedType;
  }

  @override
  w.ValueType visitStaticSet(StaticSet node, w.ValueType expectedType) {
    bool preserved = expectedType != voidMarker;
    Member target = node.target;
    if (target is Field) {
      w.Global global = translator.globals.getGlobal(target);
      wrap(node.value, global.type.type);
      b.global_set(global);
      if (preserved) {
        b.global_get(global);
        return global.type.type;
      } else {
        return voidMarker;
      }
    } else {
      w.BaseFunction targetFunction =
          translator.functions.getFunction(target.reference);
      wrap(node.value, targetFunction.type.inputs.single);
      w.Local? temp;
      if (preserved) {
        temp = addLocal(translateType(dartTypeOf(node.value)));
        b.local_tee(temp);
      }
      call(target.reference);
      if (preserved) {
        b.local_get(temp!);
        return temp.type;
      } else {
        return voidMarker;
      }
    }
  }

  @override
  w.ValueType visitSuperPropertyGet(
      SuperPropertyGet node, w.ValueType expectedType) {
    Member target = _lookupSuperTarget(node.interfaceTarget, setter: false);
    if (target is Procedure && !target.isGetter) {
      throw "Not supported: Super tear-off at ${node.location}";
    }
    return _directGet(target, ThisExpression(), () => null);
  }

  @override
  w.ValueType visitSuperPropertySet(
      SuperPropertySet node, w.ValueType expectedType) {
    Member target = _lookupSuperTarget(node.interfaceTarget, setter: true);
    return _directSet(target, ThisExpression(), node.value,
        preserved: expectedType != voidMarker);
  }

  @override
  w.ValueType visitInstanceGet(InstanceGet node, w.ValueType expectedType) {
    Member target = node.interfaceTarget;
    if (node.kind == InstanceAccessKind.Object) {
      late w.Label doneLabel;
      w.ValueType resultType = _virtualCall(node, target, (signature) {
        doneLabel = b.block(const [], signature.outputs);
        w.Label nullLabel = b.block();
        wrap(node.receiver, translator.topInfo.nullableType);
        b.br_on_null(nullLabel);
      }, (_) {}, getter: true, setter: false);
      b.br(doneLabel);
      b.end(); // nullLabel
      switch (target.name.text) {
        case "hashCode":
          b.i64_const(2011);
          break;
        case "runtimeType":
          wrap(ConstantExpression(TypeLiteralConstant(NullType())), resultType);
          break;
        default:
          unimplemented(
              node, "Nullable get of ${target.name.text}", [resultType]);
          break;
      }
      b.end(); // doneLabel
      return resultType;
    }
    Member? singleTarget = translator.singleTarget(node);
    if (singleTarget != null) {
      return _directGet(singleTarget, node.receiver,
          () => intrinsifier.generateInstanceGetterIntrinsic(node));
    } else {
      return _virtualCall(node, target,
          (signature) => wrap(node.receiver, signature.inputs.first), (_) {},
          getter: true, setter: false);
    }
  }

  @override
  w.ValueType visitDynamicGet(DynamicGet node, w.ValueType expectedType) {
    // Provisional implementation of dynamic get which assumes the getter
    // is present (otherwise it traps or calls something random) and
    // does not support tearoffs. This is sufficient to handle the
    // dynamic .length calls in the core libraries.

    SelectorInfo selector =
        translator.dispatchTable.selectorForDynamicName(node.name.text);

    // Evaluate receiver
    wrap(node.receiver, selector.signature.inputs.first);
    w.Local receiverVar = addLocal(selector.signature.inputs.first);
    b.local_tee(receiverVar);
    if (options.parameterNullability && receiverVar.type.nullable) {
      b.ref_as_non_null();
    }

    // Dispatch table call
    b.comment("Dynamic get of '${selector.name}'");
    int offset = selector.offset!;
    b.local_get(receiverVar);
    b.struct_get(translator.topInfo.struct, FieldIndex.classId);
    if (offset != 0) {
      b.i32_const(offset);
      b.i32_add();
    }
    b.call_indirect(selector.signature);

    translator.functions.activateSelector(selector);

    return translator.outputOrVoid(selector.signature.outputs);
  }

  w.ValueType _directGet(
      Member target, Expression receiver, w.ValueType? Function() intrinsify) {
    w.ValueType? intrinsicResult = intrinsify();
    if (intrinsicResult != null) return intrinsicResult;

    if (target is Field) {
      ClassInfo info = translator.classInfo[target.enclosingClass]!;
      int fieldIndex = translator.fieldIndex[target]!;
      w.ValueType receiverType = info.nullableType;
      w.ValueType fieldType = info.struct.fields[fieldIndex].type.unpacked;
      wrap(receiver, receiverType);
      b.struct_get(info.struct, fieldIndex);
      return fieldType;
    } else {
      // Instance call of getter
      assert(target is Procedure && target.isGetter);
      w.BaseFunction targetFunction =
          translator.functions.getFunction(target.reference);
      wrap(receiver, targetFunction.type.inputs.single);
      return call(target.reference);
    }
  }

  @override
  w.ValueType visitInstanceTearOff(
      InstanceTearOff node, w.ValueType expectedType) {
    return _virtualCall(node, node.interfaceTarget,
        (signature) => wrap(node.receiver, signature.inputs.first), (_) {},
        getter: true, setter: false);
  }

  @override
  w.ValueType visitInstanceSet(InstanceSet node, w.ValueType expectedType) {
    bool preserved = expectedType != voidMarker;
    w.Local? temp;
    Member? singleTarget = translator.singleTarget(node);
    if (singleTarget != null) {
      return _directSet(singleTarget, node.receiver, node.value,
          preserved: preserved);
    } else {
      _virtualCall(node, node.interfaceTarget,
          (signature) => wrap(node.receiver, signature.inputs.first),
          (signature) {
        w.ValueType paramType = signature.inputs.last;
        wrap(node.value, paramType);
        if (preserved) {
          temp = addLocal(paramType);
          b.local_tee(temp!);
        }
      }, getter: false, setter: true);
      if (preserved) {
        b.local_get(temp!);
        return temp!.type;
      } else {
        return voidMarker;
      }
    }
  }

  w.ValueType _directSet(Member target, Expression receiver, Expression value,
      {required bool preserved}) {
    w.Local? temp;
    if (target is Field) {
      ClassInfo info = translator.classInfo[target.enclosingClass]!;
      int fieldIndex = translator.fieldIndex[target]!;
      w.ValueType receiverType = info.nullableType;
      w.ValueType fieldType = info.struct.fields[fieldIndex].type.unpacked;
      wrap(receiver, receiverType);
      wrap(value, fieldType);
      if (preserved) {
        temp = addLocal(fieldType);
        b.local_tee(temp);
      }
      b.struct_set(info.struct, fieldIndex);
    } else {
      w.BaseFunction targetFunction =
          translator.functions.getFunction(target.reference);
      w.ValueType paramType = targetFunction.type.inputs.last;
      wrap(receiver, targetFunction.type.inputs.first);
      wrap(value, paramType);
      if (preserved) {
        temp = addLocal(paramType);
        b.local_tee(temp);
        translator.convertType(function, temp.type, paramType);
      }
      call(target.reference);
    }
    if (preserved) {
      b.local_get(temp!);
      return temp.type;
    } else {
      return voidMarker;
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    Capture? capture = closures.captures[node.variable];
    bool locallyClosurized = closures.closurizedFunctions.contains(node);
    if (capture != null || locallyClosurized) {
      if (capture != null) {
        b.local_get(capture.context.currentLocal);
      }
      w.StructType struct = _instantiateClosure(node.function);
      if (locallyClosurized) {
        w.Local local = addLocal(w.RefType.def(struct, nullable: false));
        locals[node.variable] = local;
        if (capture != null) {
          b.local_tee(local);
        } else {
          b.local_set(local);
        }
      }
      if (capture != null) {
        b.struct_set(capture.context.struct, capture.fieldIndex);
      }
    }
  }

  @override
  w.ValueType visitFunctionExpression(
      FunctionExpression node, w.ValueType expectedType) {
    w.StructType struct = _instantiateClosure(node.function);
    return w.RefType.def(struct, nullable: false);
  }

  w.StructType _instantiateClosure(FunctionNode functionNode) {
    int parameterCount = functionNode.requiredParameterCount;
    Lambda lambda = closures.lambdas[functionNode]!;
    w.DefinedGlobal global = translator.makeFunctionRef(lambda.function);

    ClassInfo info = translator.classInfo[translator.functionClass]!;
    translator.functions.allocateClass(info.classId);
    w.StructType struct = translator.closureStructType(parameterCount);

    b.i32_const(info.classId);
    b.i32_const(initialIdentityHash);
    _pushContext(functionNode);
    b.global_get(global);
    translator.struct_new(b, parameterCount);

    return struct;
  }

  void _pushContext(FunctionNode functionNode) {
    Context? context = closures.contexts[functionNode]?.parent;
    if (context != null) {
      b.local_get(context.currentLocal);
      if (context.currentLocal.type.nullable) {
        b.ref_as_non_null();
      }
    } else {
      b.global_get(translator.globals.dummyGlobal); // Dummy context
    }
  }

  @override
  w.ValueType visitFunctionInvocation(
      FunctionInvocation node, w.ValueType expectedType) {
    Expression receiver = node.receiver;
    if (receiver is InstanceGet &&
        receiver.interfaceTarget == translator.wasmFunctionCall) {
      // Receiver is a WasmFunction
      assert(receiver.name.text == "call");
      w.RefType receiverType =
          translator.translateType(dartTypeOf(receiver.receiver)) as w.RefType;
      w.Local temp = addLocal(receiverType);
      wrap(receiver.receiver, receiverType);
      b.local_set(temp);
      w.FunctionType functionType = receiverType.heapType as w.FunctionType;
      assert(node.arguments.positional.length == functionType.inputs.length);
      for (int i = 0; i < node.arguments.positional.length; i++) {
        wrap(node.arguments.positional[i], functionType.inputs[i]);
      }
      b.local_get(temp);
      b.call_ref();
      return translator.outputOrVoid(functionType.outputs);
    }
    int parameterCount = node.functionType?.requiredParameterCount ??
        node.arguments.positional.length;
    return _functionCall(parameterCount, receiver, node.arguments);
  }

  w.ValueType _functionCall(
      int parameterCount, Expression receiver, Arguments arguments) {
    w.StructType struct = translator.closureStructType(parameterCount);
    w.Local temp = addLocal(w.RefType.def(struct, nullable: false));
    wrap(receiver, temp.type);
    b.local_tee(temp);
    b.struct_get(struct, FieldIndex.closureContext);
    for (Expression arg in arguments.positional) {
      wrap(arg, translator.topInfo.nullableType);
    }
    b.local_get(temp);
    b.struct_get(struct, FieldIndex.closureFunction);
    b.call_ref();
    return translator.topInfo.nullableType;
  }

  @override
  w.ValueType visitLocalFunctionInvocation(
      LocalFunctionInvocation node, w.ValueType expectedType) {
    var decl = node.variable.parent as FunctionDeclaration;
    _pushContext(decl.function);
    for (Expression arg in node.arguments.positional) {
      wrap(arg, translator.topInfo.nullableType);
    }
    Lambda lambda = closures.lambdas[decl.function]!;
    b.comment("Local call of ${decl.variable.name}");
    b.call(lambda.function);
    return translator.topInfo.nullableType;
  }

  @override
  w.ValueType visitLogicalExpression(
      LogicalExpression node, w.ValueType expectedType) {
    _conditional(node, () => b.i32_const(1), () => b.i32_const(0),
        const [w.NumType.i32]);
    return w.NumType.i32;
  }

  @override
  w.ValueType visitNot(Not node, w.ValueType expectedType) {
    wrap(node.operand, w.NumType.i32);
    b.i32_eqz();
    return w.NumType.i32;
  }

  @override
  w.ValueType visitConditionalExpression(
      ConditionalExpression node, w.ValueType expectedType) {
    _conditional(
        node.condition,
        () => wrap(node.then, expectedType),
        () => wrap(node.otherwise, expectedType),
        [if (expectedType != voidMarker) expectedType]);
    return expectedType;
  }

  @override
  w.ValueType visitNullCheck(NullCheck node, w.ValueType expectedType) {
    w.ValueType operandType =
        translator.translateType(dartTypeOf(node.operand));
    w.ValueType nonNullOperandType = operandType.withNullability(false);
    w.Label nullCheckBlock = b.block(const [], [nonNullOperandType]);
    wrap(node.operand, operandType);

    // We lower a null check to a br_on_non_null, throwing a [TypeError] in the
    // null case.
    b.br_on_non_null(nullCheckBlock);
    call(translator.stackTraceCurrent.reference);
    call(translator.throwNullCheckError.reference);
    b.unreachable();
    b.end();
    return nonNullOperandType;
  }

  void _visitArguments(Arguments node, Reference target, int signatureOffset) {
    final w.FunctionType signature = translator.signatureFor(target);
    final ParameterInfo paramInfo = translator.paramInfoFor(target);
    for (int i = 0; i < node.types.length; i++) {
      types.makeType(this, node.types[i]);
    }
    signatureOffset += node.types.length;
    for (int i = 0; i < node.positional.length; i++) {
      wrap(node.positional[i], signature.inputs[signatureOffset + i]);
    }
    // Default values for positional parameters
    for (int i = node.positional.length; i < paramInfo.positional.length; i++) {
      final w.ValueType type = signature.inputs[signatureOffset + i];
      translator.constants
          .instantiateConstant(function, b, paramInfo.positional[i]!, type);
    }
    // Named arguments
    final Map<String, w.Local> namedLocals = {};
    for (var namedArg in node.named) {
      final w.ValueType type = signature
          .inputs[signatureOffset + paramInfo.nameIndex[namedArg.name]!];
      final w.Local namedLocal = addLocal(type);
      namedLocals[namedArg.name] = namedLocal;
      wrap(namedArg.value, namedLocal.type);
      b.local_set(namedLocal);
    }
    for (String name in paramInfo.names) {
      w.Local? namedLocal = namedLocals[name];
      final w.ValueType type =
          signature.inputs[signatureOffset + paramInfo.nameIndex[name]!];
      if (namedLocal != null) {
        b.local_get(namedLocal);
        translator.convertType(function, namedLocal.type, type);
      } else {
        translator.constants
            .instantiateConstant(function, b, paramInfo.named[name]!, type);
      }
    }
  }

  @override
  w.ValueType visitStringConcatenation(
      StringConcatenation node, w.ValueType expectedType) {
    makeList(node.expressions, translator.fixedLengthListClass,
        InterfaceType(translator.stringBaseClass, Nullability.nonNullable));
    return call(translator.stringInterpolate.reference);
  }

  @override
  w.ValueType visitThrow(Throw node, w.ValueType expectedType) {
    wrap(node.expression, translator.topInfo.nonNullableType);
    call(translator.stackTraceCurrent.reference);

    // At this point, we have the exception and the current stack trace on the
    // stack, so just throw them using the exception tag.
    b.throw_(translator.exceptionTag);
    return expectedType;
  }

  @override
  w.ValueType visitRethrow(Rethrow node, w.ValueType expectedType) {
    b.rethrow_(tryLabels.last);
    return expectedType;
  }

  @override
  w.ValueType visitInstantiation(Instantiation node, w.ValueType expectedType) {
    throw "Not supported: Generic function instantiation at ${node.location}";
  }

  @override
  w.ValueType visitConstantExpression(
      ConstantExpression node, w.ValueType expectedType) {
    translator.constants
        .instantiateConstant(function, b, node.constant, expectedType);
    return expectedType;
  }

  @override
  w.ValueType visitNullLiteral(NullLiteral node, w.ValueType expectedType) {
    translator.constants
        .instantiateConstant(function, b, NullConstant(), expectedType);
    return expectedType;
  }

  @override
  w.ValueType visitStringLiteral(StringLiteral node, w.ValueType expectedType) {
    translator.constants.instantiateConstant(
        function, b, StringConstant(node.value), expectedType);
    return expectedType;
  }

  @override
  w.ValueType visitBoolLiteral(BoolLiteral node, w.ValueType expectedType) {
    b.i32_const(node.value ? 1 : 0);
    return w.NumType.i32;
  }

  @override
  w.ValueType visitIntLiteral(IntLiteral node, w.ValueType expectedType) {
    b.i64_const(node.value);
    return w.NumType.i64;
  }

  @override
  w.ValueType visitDoubleLiteral(DoubleLiteral node, w.ValueType expectedType) {
    b.f64_const(node.value);
    return w.NumType.f64;
  }

  @override
  w.ValueType visitListLiteral(ListLiteral node, w.ValueType expectedType) {
    return makeList(
        node.expressions, translator.growableListClass, node.typeArgument);
  }

  w.ValueType makeList(
      List<Expression> expressions, Class cls, DartType typeArg) {
    ClassInfo info = translator.classInfo[cls]!;
    translator.functions.allocateClass(info.classId);
    w.RefType refType = info.struct.fields.last.type.unpacked as w.RefType;
    w.ArrayType arrayType = refType.heapType as w.ArrayType;
    w.ValueType elementType = arrayType.elementType.type.unpacked;
    int length = expressions.length;

    b.i32_const(info.classId);
    b.i32_const(initialIdentityHash);
    types.makeType(this, typeArg);
    b.i64_const(length);
    if (options.lazyConstants) {
      // Avoid array.init instruction in lazy constants mode
      b.i32_const(length);
      translator.array_new_default(b, arrayType);
      if (length > 0) {
        w.Local arrayLocal = addLocal(refType.withNullability(false));
        b.local_set(arrayLocal);
        for (int i = 0; i < length; i++) {
          b.local_get(arrayLocal);
          b.i32_const(i);
          wrap(expressions[i], elementType);
          b.array_set(arrayType);
        }
        b.local_get(arrayLocal);
        if (arrayLocal.type.nullable) {
          b.ref_as_non_null();
        }
      }
    } else {
      for (Expression expression in expressions) {
        wrap(expression, elementType);
      }
      translator.array_init(b, arrayType, length);
    }
    translator.struct_new(b, info);

    return info.nonNullableType;
  }

  @override
  w.ValueType visitMapLiteral(MapLiteral node, w.ValueType expectedType) {
    w.BaseFunction mapFactory =
        translator.functions.getFunction(translator.mapFactory.reference);
    w.ValueType factoryReturnType = mapFactory.type.outputs.single;
    types.makeType(this, node.keyType);
    types.makeType(this, node.valueType);
    b.call(mapFactory);
    if (node.entries.isEmpty) {
      return factoryReturnType;
    }
    w.BaseFunction mapPut =
        translator.functions.getFunction(translator.mapPut.reference);
    w.ValueType putReceiverType = mapPut.type.inputs[0];
    w.ValueType putKeyType = mapPut.type.inputs[1];
    w.ValueType putValueType = mapPut.type.inputs[2];
    w.Local mapLocal = addLocal(putReceiverType);
    translator.convertType(function, factoryReturnType, mapLocal.type);
    b.local_set(mapLocal);
    for (MapLiteralEntry entry in node.entries) {
      b.local_get(mapLocal);
      translator.convertType(function, mapLocal.type, putReceiverType);
      wrap(entry.key, putKeyType);
      wrap(entry.value, putValueType);
      b.call(mapPut);
    }
    b.local_get(mapLocal);
    return mapLocal.type;
  }

  @override
  w.ValueType visitSetLiteral(SetLiteral node, w.ValueType expectedType) {
    w.BaseFunction setFactory =
        translator.functions.getFunction(translator.setFactory.reference);
    w.ValueType factoryReturnType = setFactory.type.outputs.single;
    types.makeType(this, node.typeArgument);
    b.call(setFactory);
    if (node.expressions.isEmpty) {
      return factoryReturnType;
    }
    w.BaseFunction setAdd =
        translator.functions.getFunction(translator.setAdd.reference);
    w.ValueType addReceiverType = setAdd.type.inputs[0];
    w.ValueType addKeyType = setAdd.type.inputs[1];
    w.Local setLocal = addLocal(addReceiverType);
    translator.convertType(function, factoryReturnType, setLocal.type);
    b.local_set(setLocal);
    for (Expression element in node.expressions) {
      b.local_get(setLocal);
      translator.convertType(function, setLocal.type, addReceiverType);
      wrap(element, addKeyType);
      b.call(setAdd);
      b.drop();
    }
    b.local_get(setLocal);
    return setLocal.type;
  }

  @override
  w.ValueType visitTypeLiteral(TypeLiteral node, w.ValueType expectedType) {
    return types.makeType(this, node.type);
  }

  @override
  w.ValueType visitIsExpression(IsExpression node, w.ValueType expectedType) {
    wrap(node.operand, translator.topInfo.nullableType);
    types.emitTypeTest(this, node.type, dartTypeOf(node.operand), node);
    return w.NumType.i32;
  }

  @override
  w.ValueType visitAsExpression(AsExpression node, w.ValueType expectedType) {
    w.Label asCheckBlock = b.block();
    wrap(node.operand, translator.topInfo.nullableType);
    w.Local operand = addLocal(translator.topInfo.nullableType);
    b.local_tee(operand);

    // We lower an `as` expression to a type test, throwing a [TypeError] if
    // the type test fails.
    types.emitTypeTest(this, node.type, dartTypeOf(node.operand), node);
    b.br_if(asCheckBlock);
    b.local_get(operand);
    types.makeType(this, node.type);
    call(translator.stackTraceCurrent.reference);
    call(translator.throwAsCheckError.reference);
    b.unreachable();
    b.end();
    b.local_get(operand);
    return operand.type;
  }

  w.ValueType instantiateTypeParameter(TypeParameter parameter) {
    w.ValueType resultType;
    if (parameter.parent is FunctionNode) {
      // Type argument to function
      w.Local? local = typeLocals[parameter];
      if (local != null) {
        b.local_get(local);
        resultType = local.type;
      } else {
        Capture capture = closures.captures[parameter]!;
        b.local_get(capture.context.currentLocal);
        b.struct_get(capture.context.struct, capture.fieldIndex);
        resultType = capture.type;
      }
    } else {
      // Type argument of class
      Class cls = parameter.parent as Class;
      ClassInfo info = translator.classInfo[cls]!;
      int fieldIndex = translator.typeParameterIndex[parameter]!;
      w.ValueType thisType = visitThis(info.nonNullableType);
      translator.convertType(function, thisType, info.nonNullableType);
      b.struct_get(info.struct, fieldIndex);
      resultType = info.struct.fields[fieldIndex].type.unpacked;
    }
    final w.ValueType nonNullableTypeType =
        translator.classInfo[translator.typeClass]!.nonNullableType;
    translator.convertType(function, resultType, nonNullableTypeType);
    return nonNullableTypeType;
  }
}

class TryBlockFinalizer {
  final w.Label label;
  bool mustHandleReturn = false;

  TryBlockFinalizer(this.label);
}

/// Holds information of a switch statement, to be used when doing a backward
/// jump to it
class SwitchBackwardJumpInfo {
  /// Wasm local for the value of the switched expression. For example, in a
  /// `switch` like:
  ///
  /// ```
  /// switch (expr) {
  ///   ...
  /// }
  /// ```
  ///
  /// This local holds the value of `expr`.
  ///
  /// This local is updated with a new value when doing backward jumps.
  final w.Local switchValueLocal;

  /// Label of the `loop` to use when doing backward jumps
  final w.Label loopLabel;

  /// When compiling a `default` case, label of the `loop` in the case body, to
  /// use when doing backward jumps to the same case.
  w.Label? defaultLoopLabel;

  SwitchBackwardJumpInfo(this.switchValueLocal, this.loopLabel)
      : defaultLoopLabel = null;
}
