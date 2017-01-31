// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.parser.listener;

import 'package:front_end/src/fasta/scanner/token.dart' show
    BeginGroupToken,
    Token;

import 'error_kind.dart' show
    ErrorKind;

/// A parser event listener that does nothing except throw exceptions
/// on parser errors.
///
/// Events are methods that begin with one of: `begin`, `end`, or `handle`.
///
/// Events starting with `begin` and `end` come in pairs. Normally, a
/// `beginFoo` event is followed by an `endFoo` event. There's a few exceptions
/// documented below.
///
/// Events starting with `handle` are used when isn't possible to have a begin
/// event.
class Listener {
  final List<ParserError> recoverableErrors = <ParserError>[];

  void logEvent(String name) {}

  set suppressParseErrors(bool value) {}

  void beginArguments(Token token) {}

  void endArguments(int count, Token beginToken, Token endToken) {
    logEvent("Arguments");
  }

  /// Handle async modifiers `async`, `async*`, `sync`.
  void handleAsyncModifier(Token asyncToken, Token starToken) {
    logEvent("AsyncModifier");
  }

  void beginAwaitExpression(Token token) {}

  void endAwaitExpression(Token beginToken, Token endToken) {
    logEvent("AwaitExpression");
  }

  void beginBlock(Token token) {}

  void endBlock(int count, Token beginToken, Token endToken) {
    logEvent("Block");
  }

  void beginCascade(Token token) {}

  void endCascade() {
    logEvent("Cascade");
  }

  void beginClassBody(Token token) {}

  void endClassBody(int memberCount, Token beginToken, Token endToken) {
    logEvent("ClassBody");
  }

  void beginClassDeclaration(Token token) {}

  void endClassDeclaration(int interfacesCount, Token beginToken,
      Token extendsKeyword, Token implementsKeyword, Token endToken) {
    logEvent("ClassDeclaration");
  }

  void beginCombinators(Token token) {}

  void endCombinators(int count) {
    logEvent("Combinators");
  }

  void beginCompilationUnit(Token token) {}

  void endCompilationUnit(int count, Token token) {
    logEvent("CompilationUnit");
  }

  void beginConstructorReference(Token start) {}

  void endConstructorReference(
      Token start, Token periodBeforeName, Token endToken) {
    logEvent("ConstructorReference");
  }

  void beginDoWhileStatement(Token token) {}

  void endDoWhileStatement(
      Token doKeyword, Token whileKeyword, Token endToken) {
    logEvent("DoWhileStatement");
  }

  void beginDoWhileStatementBody(Token token) {
  }

  void endDoWhileStatementBody(Token token) {
    logEvent("DoWhileStatementBody");
  }

  void beginWhileStatementBody(Token token) {
  }

  void endWhileStatementBody(Token token) {
    logEvent("WhileStatementBody");
  }

  void beginEnum(Token enumKeyword) {}

  void endEnum(Token enumKeyword, Token endBrace, int count) {
    logEvent("Enum");
  }

  void beginExport(Token token) {}

  void endExport(Token exportKeyword, Token semicolon) {
    logEvent("Export");
  }

  void beginExpression(Token token) {}

  void beginExpressionStatement(Token token) {}

  void endExpressionStatement(Token token) {
    logEvent("ExpressionStatement");
  }

  void beginFactoryMethod(Token token) {}

  void endFactoryMethod(Token beginToken, Token endToken) {
    logEvent("FactoryMethod");
  }

  void beginFormalParameter(Token token) {}

  void endFormalParameter(Token thisKeyword) {
    logEvent("FormalParameter");
  }

  void handleNoFormalParameters(Token token) {
    logEvent("NoFormalParameters");
  }

  void beginFormalParameters(Token token) {}

  void endFormalParameters(int count, Token beginToken, Token endToken) {
    logEvent("FormalParameters");
  }

  /// Doesn't have a corresponding begin event, use [beginMember] instead.
  void endFields(int count, Token beginToken, Token endToken) {
    logEvent("Fields");
  }

  void beginForStatement(Token token) {}

  void endForStatement(
      int updateExpressionCount, Token beginToken, Token endToken) {
    logEvent("ForStatement");
  }

  void beginForStatementBody(Token token) {
  }

  void endForStatementBody(Token token) {
    logEvent("ForStatementBody");
  }

  void endForIn(
      Token awaitToken, Token forToken, Token inKeyword, Token endToken) {
    logEvent("ForIn");
  }

  void beginForInExpression(Token token) {
  }

  void endForInExpression(Token token) {
    logEvent("ForInExpression");
  }

  void beginForInBody(Token token) {
  }

  void endForInBody(Token token) {
    logEvent("ForInBody");
  }

  void beginFunction(Token token) {}

  void endFunction(Token getOrSet, Token endToken) {
    logEvent("Function");
  }

  void beginFunctionDeclaration(Token token) {}

  void endFunctionDeclaration(Token token) {
    logEvent("FunctionDeclaration");
  }

  void beginFunctionBody(Token token) {}

  void endFunctionBody(int count, Token beginToken, Token endToken) {
    logEvent("FunctionBody");
  }

  void handleNoFunctionBody(Token token) {
    logEvent("NoFunctionBody");
  }

  void handleFunctionBodySkipped(Token token) {}

  void beginFunctionName(Token token) {}

  void endFunctionName(Token token) {
    logEvent("FunctionName");
  }

  void beginFunctionTypeAlias(Token token) {}

  void endFunctionTypeAlias(Token typedefKeyword, Token endToken) {
    logEvent("FunctionTypeAlias");
  }

  void beginMixinApplication(Token token) {}

  void endMixinApplication() {
    logEvent("MixinApplication");
  }

  void beginNamedMixinApplication(Token token) {}

  void endNamedMixinApplication(
      Token classKeyword, Token implementsKeyword, Token endToken) {
    logEvent("NamedMixinApplication");
  }

  void beginHide(Token hideKeyword) {}

  void endHide(Token hideKeyword) {
    logEvent("Hide");
  }

  void beginIdentifierList(Token token) {}

  void endIdentifierList(int count) {
    logEvent("IdentifierList");
  }

  void beginTypeList(Token token) {}

  void endTypeList(int count) {
    logEvent("TypeList");
  }

  void beginIfStatement(Token token) {}

  void endIfStatement(Token ifToken, Token elseToken) {
    logEvent("IfStatement");
  }

  void beginThenStatement(Token token) {
  }

  void endThenStatement(Token token) {
    logEvent("ThenStatement");
  }

  void beginElseStatement(Token token) {
  }

  void endElseStatement(Token token) {
    logEvent("ElseStatement");
  }

  void beginImport(Token importKeyword) {}

  void endImport(Token importKeyword, Token DeferredKeyword, Token asKeyword,
      Token semicolon) {
    logEvent("Import");
  }

  void beginConditionalUris(Token token) {}

  void endConditionalUris(int count) {
    logEvent("ConditionalUris");
  }

  void beginConditionalUri(Token ifKeyword) {}

  void endConditionalUri(Token ifKeyword, Token equalitySign) {
    logEvent("ConditionalUri");
  }

  void beginDottedName(Token token) {}

  void endDottedName(int count, Token firstIdentifier) {
    logEvent("DottedName");
  }

  void beginInitializedIdentifier(Token token) {}

  void endInitializedIdentifier() {
    logEvent("InitializedIdentifier");
  }

  void beginFieldInitializer(Token token) {
  }

  void endFieldInitializer(Token assignment) {
    logEvent("FieldInitializer");
  }

  void handleNoFieldInitializer(Token token) {
    logEvent("NoFieldInitializer");
  }

  void beginVariableInitializer(Token token) {}

  void endVariableInitializer(Token assignmentOperator) {
    logEvent("VariableInitializer");
  }

  void beginInitializer(Token token) {}

  void endInitializer(Token token) {
    logEvent("ConstructorInitializer");
  }

  void beginInitializers(Token token) {}

  void endInitializers(int count, Token beginToken, Token endToken) {
    logEvent("Initializers");
  }

  void handleNoInitializers() {
    logEvent("NoInitializers");
  }

  /// Called after the listener has recovered from an invalid expression. The
  /// parser will resume parsing from [token]. Exactly where the parser will
  /// resume parsing is unspecified.
  void handleInvalidExpression(Token token) {
    logEvent("InvalidExpression");
  }

  /// Called after the listener has recovered from an invalid function
  /// body. The parser expected an open curly brace `{` and will resume parsing
  /// from [token] as if a function body had preceeded it.
  void handleInvalidFunctionBody(Token token) {
    logEvent("InvalidFunctionBody");
  }

  /// Called after the listener has recovered from an invalid type. The parser
  /// expected an identifier, and will resume parsing type arguments from
  /// [token].
  void handleInvalidTypeReference(Token token) {
    logEvent("InvalidTypeReference");
  }

  void handleLabel(Token token) {
    logEvent("Label");
  }

  void beginLabeledStatement(Token token, int labelCount) {}

  void endLabeledStatement(int labelCount) {
    logEvent("LabeledStatement");
  }

  void beginLibraryName(Token token) {}

  void endLibraryName(Token libraryKeyword, Token semicolon) {
    logEvent("LibraryName");
  }

  void beginLiteralMapEntry(Token token) {}

  void endLiteralMapEntry(Token colon, Token endToken) {
    logEvent("LiteralMapEntry");
  }

  void beginLiteralString(Token token) {}

  void endLiteralString(int interpolationCount) {
    logEvent("LiteralString");
  }

  void handleStringJuxtaposition(int literalCount) {
    logEvent("StringJuxtaposition");
  }

  void beginMember(Token token) {}

  /// This event is added for convenience. Normally, one should override
  /// [endMethod] or [endFields] instead.
  void endMember() {
    logEvent("Member");
  }

  /// Doesn't have a corresponding begin event, use [beginMember] instead.
  void endMethod(Token getOrSet, Token beginToken, Token endToken) {
    logEvent("Method");
  }

  void beginMetadataStar(Token token) {}

  void endMetadataStar(int count, bool forParameter) {
    logEvent("MetadataStar");
  }

  void beginMetadata(Token token) {}

  void endMetadata(Token beginToken, Token periodBeforeName, Token endToken) {
    logEvent("Metadata");
  }

  void beginOptionalFormalParameters(Token token) {}

  void endOptionalFormalParameters(
      int count, Token beginToken, Token endToken) {
    logEvent("OptionalFormalParameters");
  }

  void beginPart(Token token) {}

  void endPart(Token partKeyword, Token semicolon) {
    logEvent("Part");
  }

  void beginPartOf(Token token) {}

  void endPartOf(Token partKeyword, Token semicolon) {
    logEvent("PartOf");
  }

  void beginRedirectingFactoryBody(Token token) {}

  void endRedirectingFactoryBody(Token beginToken, Token endToken) {
    logEvent("RedirectingFactoryBody");
  }

  void beginReturnStatement(Token token) {}

  void endReturnStatement(
      bool hasExpression, Token beginToken, Token endToken) {
    logEvent("ReturnStatement");
  }

  void beginSend(Token token) {}

  void endSend(Token token) {
    logEvent("Send");
  }

  void beginShow(Token showKeyword) {}

  void endShow(Token showKeyword) {
    logEvent("Show");
  }

  void beginSwitchStatement(Token token) {}

  void endSwitchStatement(Token switchKeyword, Token endToken) {
    logEvent("SwitchStatement");
  }

  void beginSwitchBlock(Token token) {}

  void endSwitchBlock(int caseCount, Token beginToken, Token endToken) {
    logEvent("SwitchBlock");
  }

  void beginLiteralSymbol(Token token) {}

  void endLiteralSymbol(Token hashToken, int identifierCount) {
    logEvent("LiteralSymbol");
  }

  void beginThrowExpression(Token token) {}

  void endThrowExpression(Token throwToken, Token endToken) {
    logEvent("ThrowExpression");
  }

  void beginRethrowStatement(Token token) {}

  void endRethrowStatement(Token throwToken, Token endToken) {
    logEvent("RethrowStatement");
  }

  /// This event is added for convenience. Normally, one should use
  /// [endClassDeclaration], [endNamedMixinApplication], [endEnum],
  /// [endFunctionTypeAlias], [endLibraryName], [endImport], [endExport],
  /// [endPart], [endPartOf], [endTopLevelFields], or [endTopLevelMethod].
  void endTopLevelDeclaration(Token token) {
    logEvent("TopLevelDeclaration");
  }

  void beginTopLevelMember(Token token) {}

  /// Doesn't have a corresponding begin event, use [beginTopLevelMember]
  /// instead.
  void endTopLevelFields(int count, Token beginToken, Token endToken) {
    logEvent("TopLevelFields");
  }

  /// Doesn't have a corresponding begin event, use [beginTopLevelMember]
  /// instead.
  void endTopLevelMethod(Token beginToken, Token getOrSet, Token endToken) {
    logEvent("TopLevelMethod");
  }

  void beginTryStatement(Token token) {}

  void handleCaseMatch(Token caseKeyword, Token colon) {
    logEvent("CaseMatch");
  }

  void beginCatchClause(Token token) {
  }

  void endCatchClause(Token token) {
    logEvent("CatchClause");
  }

  void handleCatchBlock(Token onKeyword, Token catchKeyword) {
    logEvent("CatchBlock");
  }

  void handleFinallyBlock(Token finallyKeyword) {
    logEvent("FinallyBlock");
  }

  void endTryStatement(
      int catchCount, Token tryKeyword, Token finallyKeyword) {
    logEvent("TryStatement");
  }

  void endType(Token beginToken, Token endToken) {
    logEvent("Type");
  }

  void beginTypeArguments(Token token) {}

  void endTypeArguments(int count, Token beginToken, Token endToken) {
    logEvent("TypeArguments");
  }

  void handleNoTypeArguments(Token token) {
    logEvent("NoTypeArguments");
  }

  void beginTypeVariable(Token token) {}

  void endTypeVariable(Token token, Token extendsOrSuper) {
    logEvent("TypeVariable");
  }

  void beginTypeVariables(Token token) {}

  void endTypeVariables(int count, Token beginToken, Token endToken) {
    logEvent("TypeVariables");
  }

  void beginUnnamedFunction(Token token) {}

  void endUnnamedFunction(Token token) {
    logEvent("UnnamedFunction");
  }

  void beginVariablesDeclaration(Token token) {}

  void endVariablesDeclaration(int count, Token endToken) {
    logEvent("VariablesDeclaration");
  }

  void beginWhileStatement(Token token) {}

  void endWhileStatement(Token whileKeyword, Token endToken) {
    logEvent("WhileStatement");
  }

  void handleAsOperator(Token operator, Token endToken) {
    logEvent("AsOperator");
  }

  void handleAssignmentExpression(Token token) {
    logEvent("AssignmentExpression");
  }

  void handleBinaryExpression(Token token) {
    logEvent("BinaryExpression");
  }

  void handleConditionalExpression(Token question, Token colon) {
    logEvent("ConditionalExpression");
  }

  void handleConstExpression(Token token) {
    logEvent("ConstExpression");
  }

  void beginFunctionTypedFormalParameter(Token token) {
  }

  void endFunctionTypedFormalParameter(Token token) {
    logEvent("FunctionTypedFormalParameter");
  }

  void handleIdentifier(Token token) {
    logEvent("Identifier");
  }

  void handleIndexedExpression(
      Token openCurlyBracket, Token closeCurlyBracket) {
    logEvent("IndexedExpression");
  }

  void handleIsOperator(Token operator, Token not, Token endToken) {
    logEvent("IsOperator");
  }

  void handleLiteralBool(Token token) {
    logEvent("LiteralBool");
  }

  void handleBreakStatement(
      bool hasTarget, Token breakKeyword, Token endToken) {
    logEvent("BreakStatement");
  }

  void handleContinueStatement(
      bool hasTarget, Token continueKeyword, Token endToken) {
    logEvent("ContinueStatement");
  }

  void handleEmptyStatement(Token token) {
    logEvent("EmptyStatement");
  }

  void handleAssertStatement(
      Token assertKeyword, Token commaToken, Token semicolonToken) {
    logEvent("AssertStatement");
  }

  /** Called with either the token containing a double literal, or
    * an immediately preceding "unary plus" token.
    */
  void handleLiteralDouble(Token token) {
    logEvent("LiteralDouble");
  }

  /** Called with either the token containing an integer literal,
    * or an immediately preceding "unary plus" token.
    */
  void handleLiteralInt(Token token) {
    logEvent("LiteralInt");
  }

  void handleLiteralList(
      int count, Token beginToken, Token constKeyword, Token endToken) {
    logEvent("LiteralList");
  }

  void handleLiteralMap(
      int count, Token beginToken, Token constKeyword, Token endToken) {
    logEvent("LiteralMap");
  }

  void handleLiteralNull(Token token) {
    logEvent("LiteralNull");
  }

  void handleModifier(Token token) {
    logEvent("Modifier");
  }

  void handleModifiers(int count) {
    logEvent("Modifiers");
  }

  void handleNamedArgument(Token colon) {
    logEvent("NamedArgument");
  }

  void handleNewExpression(Token token) {
    logEvent("NewExpression");
  }

  void handleNoArguments(Token token) {
    logEvent("NoArguments");
  }

  void handleNoExpression(Token token) {
    logEvent("NoExpression");
  }

  void handleNoType(Token token) {
    logEvent("NoType");
  }

  void handleNoTypeVariables(Token token) {
    logEvent("NoTypeVariables");
  }

  void handleOperator(Token token) {
    logEvent("Operator");
  }

  void handleOperatorName(Token operatorKeyword, Token token) {
    logEvent("OperatorName");
  }

  void handleParenthesizedExpression(BeginGroupToken token) {
    logEvent("ParenthesizedExpression");
  }

  void handleQualified(Token period) {
    logEvent("Qualified");
  }

  void handleStringPart(Token token) {
    logEvent("StringPart");
  }

  void handleSuperExpression(Token token) {
    logEvent("SuperExpression");
  }

  void beginSwitchCase(int labelCount, int expressionCount, Token firstToken) {
  }

  void handleSwitchCase(
      int labelCount,
      int expressionCount,
      Token defaultKeyword,
      int statementCount,
      Token firstToken,
      Token endToken) {
    logEvent("SwitchCase");
  }

  void handleThisExpression(Token token) {
    logEvent("ThisExpression");
  }

  void handleUnaryPostfixAssignmentExpression(Token token) {
    logEvent("UnaryPostfixAssignmentExpression");
  }

  void handleUnaryPrefixExpression(Token token) {
    logEvent("UnaryPrefixExpression");
  }

  void handleUnaryPrefixAssignmentExpression(Token token) {
    logEvent("UnaryPrefixAssignmentExpression");
  }

  void handleValuedFormalParameter(Token equals, Token token) {
    logEvent("ValuedFormalParameter");
  }

  void handleVoidKeyword(Token token) {
    logEvent("VoidKeyword");
  }

  void beginYieldStatement(Token token) {}

  void endYieldStatement(Token yieldToken, Token starToken, Token endToken) {
    logEvent("YieldStatement");
  }

  /// An unrecoverable error is an error that the parser can't recover from
  /// itself, and recovery is left to the listener. If the listener can
  /// recover, it should return a non-null continuation token. Error recovery
  /// is tightly coupled to the parser implementation, so to recover from an
  /// error, one must carefully examine the code in the parser that generates
  /// the error.
  ///
  /// If the listener can't recover, it can throw an exception or return
  /// `null`. In the latter case, the parser simply skips to EOF which will
  /// often result in additional parser errors as the parser returns from its
  /// recursive state.
  Token handleUnrecoverableError(Token token, ErrorKind kind, Map arguments) {
    throw new ParserError.fromTokens(token, token, kind, arguments);
  }

  /// The parser noticed a syntax error, but was able to recover from it.
  void handleRecoverableError(Token token, ErrorKind kind, Map arguments) {
    recoverableErrors.add(
        new ParserError.fromTokens(token, token, kind, arguments));
  }
}

class ParserError {
  /// Character offset from the beginning of file where this error starts.
  final int beginOffset;

  /// Character offset from the beginning of file where this error ends.
  final int endOffset;

  final ErrorKind kind;

  final Map arguments;

  ParserError(this.beginOffset, this.endOffset, this.kind, this.arguments);

  ParserError.fromTokens(Token begin, Token end, ErrorKind kind, Map arguments)
      : this(begin.charOffset, end.charOffset + end.charCount, kind,
          arguments);

  String toString() => "@${beginOffset}: $kind $arguments";
}
