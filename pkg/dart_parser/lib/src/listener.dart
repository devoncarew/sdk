// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart_parser.listener;

import 'package:dart_scanner/src/precedence.dart' show
    EOF_INFO,
    IDENTIFIER_INFO;

import 'package:dart_scanner/src/token.dart' show
    BadInputToken,
    BeginGroupToken,
    ErrorToken,
    StringToken,
    Token,
    UnmatchedToken,
    UnterminatedToken;

import 'error_kind.dart' show
    ErrorKind;

/**
 * A parser event listener that does nothing except throw exceptions
 * on parser errors.
 */
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

  void skippedFunctionBody(Token token) {}

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

  // TODO(ahe): Rename this to beginVariableInitializer.
  void beginInitializer(Token token) {}

  // TODO(ahe): Rename this to endVariableInitializer.
  void endInitializer(Token assignmentOperator) {
    logEvent("Initializer");
  }

  // TODO(ahe): Rename this to beginInitializer.
  void beginConstructorInitializer(Token token) {}

  // TODO(ahe): Rename this to endInitializer.
  void endConstructorInitializer(Token token) {
    logEvent("ConstructorInitializer");
  }

  void beginInitializers(Token token) {}

  void endInitializers(int count, Token beginToken, Token endToken) {
    logEvent("Initializers");
  }

  void handleNoInitializers() {
    logEvent("NoInitializers");
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

  void endMember() {
    logEvent("Member");
  }

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

  void endTopLevelDeclaration(Token token) {
    logEvent("TopLevelDeclaration");
  }

  void beginTopLevelMember(Token token) {}

  void endTopLevelFields(int count, Token beginToken, Token endToken) {
    logEvent("TopLevelFields");
  }

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

  // TODO(ahe): Rename to `endFunctionTypedFormalParameter`.
  void handleFunctionTypedFormalParameter(Token token) {
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

  Token expected(String string, Token token) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      error("expected '$string', but got '${token.value}'", token);
    }
    return skipToEof(token);
  }

  Token synthesizeIdentifier(Token token) {
    Token synthesizedToken = new StringToken.fromString(
        IDENTIFIER_INFO, '?', token.charOffset);
    synthesizedToken.next = token.next;
    return synthesizedToken;
  }

  Token expectedIdentifier(Token token) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      error("expected identifier, but got '${token.value}'", token);
    }
    return skipToEof(token);
  }

  Token expectedType(Token token) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      error("expected a type, but got '${token.value}'", token);
    }
    return skipToEof(token);
  }

  Token expectedExpression(Token token) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      error("expected an expression, but got '${token.value}'", token);
    }
    return skipToEof(token);
  }

  Token unexpected(Token token) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      error("unexpected token '${token.value}'", token);
    }
    return skipToEof(token);
  }

  Token expectedBlockToSkip(Token token) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      error("expected a block, but got '${token.value}'", token);
    }
    return skipToEof(token);
  }

  Token expectedFunctionBody(Token token) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      error("expected a function body, but got '${token.value}'", token);
    }
    return skipToEof(token);
  }

  Token expectedClassBody(Token token) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      error("expected a class body, but got '${token.value}'", token);
    }
    return skipToEof(token);
  }

  Token expectedClassBodyToSkip(Token token) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      error("expected a class body, but got '${token.value}'", token);
    }
    return skipToEof(token);
  }

  Token expectedDeclaration(Token token) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      error("expected a declaration, but got '${token.value}'", token);
    }
    return skipToEof(token);
  }

  Token unmatched(Token token) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      error("unmatched '${token.value}'", token);
    }
    return skipToEof(token);
  }

  skipToEof(Token token) {
    while (!identical(token.info, EOF_INFO)) {
      token = token.next;
    }
    return token;
  }

  void error(String message, Token token) {
    throw new ParserError(token, ErrorKind.UNSPECIFIED, {'text': message});
  }

  void reportError(Token token, ErrorKind kind, [Map arguments = const {}]) {
    if (token is ErrorToken) {
      reportErrorToken(token);
    } else {
      reportErrorHelper(token, kind, arguments);
    }
  }

  void reportErrorHelper(Token token, ErrorKind kind, Map arguments) {
    recoverableErrors.add(new ParserError(token, kind, arguments));
  }

  void reportErrorToken(ErrorToken token) {
    if (token is BadInputToken) {
      String hex = token.character.toRadixString(16);
      if (hex.length < 4) {
        String padding = "0000".substring(hex.length);
        hex = "$padding$hex";
      }
      reportErrorHelper(
          token, ErrorKind.INVALID_INPUT_CHARACTER, {'characterHex': hex});
    } else if (token is UnterminatedToken) {
      ErrorKind kind;
      var arguments = const {};
      switch (token.start) {
        case '1e':
          kind = ErrorKind.MISSING_EXPONENT;
          break;
        case '"':
        case "'":
        case '"""':
        case "'''":
        case 'r"':
        case "r'":
        case 'r"""':
        case "r'''":
          kind = ErrorKind.UNTERMINATED_STRING;
          arguments = {'quote': token.start};
          break;
        case '0x':
          kind = ErrorKind.EXPECTED_HEX_DIGIT;
          break;
        case r'$':
          kind = ErrorKind.MALFORMED_STRING_LITERAL;
          break;
        case '/*':
          kind = ErrorKind.UNTERMINATED_COMMENT;
          break;
        default:
          kind = ErrorKind.UNTERMINATED_TOKEN;
          break;
      }
      reportErrorHelper(token, kind, arguments);
    } else if (token is UnmatchedToken) {
      String begin = token.begin.value;
      String end = closeBraceFor(begin);
      reportErrorHelper(
          token, ErrorKind.UNMATCHED_TOKEN, {'begin': begin, 'end': end});
    } else {
      error(token.assertionMessage, token);
    }
  }
}

String closeBraceFor(String openBrace) {
  return const {
    '(': ')',
    '[': ']',
    '{': '}',
    '<': '>',
    r'${': '}',
  }[openBrace];
}

class ParserError {
  final Token token;

  final ErrorKind kind;

  final Map arguments;

  ParserError(this.token, this.kind, this.arguments);

  String toString() => "@${token.charOffset}: $kind $arguments";
}
