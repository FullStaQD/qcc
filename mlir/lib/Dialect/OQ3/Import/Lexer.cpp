// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "Lexer.h"

#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSwitch.h"

#include <optional>

using namespace qcc::oq3::detail;
using llvm::StringRef;

std::optional<Token> Lexer::skipWhitespaceAndComments() {
  while (!atEnd()) {
    const char c = peek();
    if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
      ++current;
      continue;
    }
    if (c == '/' && peek(1) == '/') {
      const char* start = current;
      while (!atEnd() && peek() != '\n' && peek() != '\r') {
        ++current;
      }
      comments.emplace_back(start, current - start);
      continue;
    }
    if (c == '/' && peek(1) == '*') {
      const char* start = current;
      const size_t end = StringRef(current + 2, buffer.end() - current - 2).find("*/");
      if (end == StringRef::npos) {
        current = buffer.end();
        return makeError(start, "unterminated block comment");
      }
      current += 2 + end + 2;
      comments.emplace_back(start, current - start);
      continue;
    }
    break;
  }
  return std::nullopt;
}

StringRef Lexer::lexRestOfLine() {
  while (!atEnd() && (peek() == ' ' || peek() == '\t')) {
    ++current;
  }
  const char* start = current;
  while (!atEnd() && peek() != '\n' && peek() != '\r') {
    ++current;
  }
  return {start, static_cast<size_t>(current - start)};
}

Token Lexer::lex() {
  if (std::optional<Token> error = skipWhitespaceAndComments()) {
    return *error;
  }
  if (atEnd()) {
    return makeToken(TokenKind::Eof, current);
  }

  const char* start = current;
  const char c = *current++;

  if (isIdentifierStart(c)) {
    return lexIdentifierOrKeyword(start);
  }
  if (llvm::isDigit(c) || (c == '.' && llvm::isDigit(peek()))) {
    return lexNumber(start);
  }

  // Applies `kind` if the next character is `next`, otherwise `otherwise`.
  auto either = [&](char next, TokenKind kind, TokenKind otherwise) {
    if (peek() == next) {
      ++current;
      return makeToken(kind, start);
    }
    return makeToken(otherwise, start);
  };
  // Lexes an operator `op` that also has the compound assignment `op=`.
  auto withAssign = [&](TokenKind kind) {
    if (peek() == '=') {
      ++current;
      return makeToken(TokenKind::CompoundAssign, start);
    }
    return makeToken(kind, start);
  };

  switch (c) {
  case '[':
    return makeToken(TokenKind::LBracket, start);
  case ']':
    return makeToken(TokenKind::RBracket, start);
  case '{':
    return makeToken(TokenKind::LBrace, start);
  case '}':
    return makeToken(TokenKind::RBrace, start);
  case '(':
    return makeToken(TokenKind::LParen, start);
  case ')':
    return makeToken(TokenKind::RParen, start);
  case ':':
    return makeToken(TokenKind::Colon, start);
  case ';':
    return makeToken(TokenKind::Semicolon, start);
  case '.':
    return makeToken(TokenKind::Dot, start);
  case ',':
    return makeToken(TokenKind::Comma, start);
  case '~':
    return makeToken(TokenKind::Tilde, start);
  case '=':
    return either('=', TokenKind::EqualEqual, TokenKind::Equals);
  case '!':
    return either('=', TokenKind::NotEqual, TokenKind::Exclamation);
  case '-':
    if (peek() == '>') {
      ++current;
      return makeToken(TokenKind::Arrow, start);
    }
    return withAssign(TokenKind::Minus);
  case '+':
    if (peek() == '+') {
      ++current;
      return makeToken(TokenKind::DoublePlus, start);
    }
    return withAssign(TokenKind::Plus);
  case '*':
    if (peek() == '*') {
      ++current;
      return withAssign(TokenKind::DoubleAsterisk);
    }
    return withAssign(TokenKind::Asterisk);
  case '/':
    return withAssign(TokenKind::Slash);
  case '%':
    return withAssign(TokenKind::Percent);
  case '^':
    return withAssign(TokenKind::Caret);
  case '|':
    if (peek() == '|') {
      ++current;
      return makeToken(TokenKind::DoublePipe, start);
    }
    return withAssign(TokenKind::Pipe);
  case '&':
    if (peek() == '&') {
      ++current;
      return makeToken(TokenKind::DoubleAmpersand, start);
    }
    return withAssign(TokenKind::Ampersand);
  case '<':
    if (peek() == '<') {
      ++current;
      return withAssign(TokenKind::ShiftLeft);
    }
    return either('=', TokenKind::LessEqual, TokenKind::Less);
  case '>':
    if (peek() == '>') {
      ++current;
      return withAssign(TokenKind::ShiftRight);
    }
    return either('=', TokenKind::GreaterEqual, TokenKind::Greater);
  case '"':
  case '\'':
    return lexString(start);
  case '$':
    if (!llvm::isDigit(peek())) {
      return makeError(start, "expected the index of a physical qubit after '$'");
    }
    while (llvm::isDigit(peek())) {
      ++current;
    }
    return makeToken(TokenKind::HardwareQubit, start);
  case '@':
    if (!isIdentifierStart(peek())) {
      return makeToken(TokenKind::At, start);
    }
    // An annotation keyword: `@` followed by a dotted identifier.
    do {
      ++current;
      while (isIdentifierChar(peek())) {
        ++current;
      }
    } while (peek() == '.' && isIdentifierStart(peek(1)) && (++current, true));
    return makeToken(TokenKind::Annotation, start);
  case '#': {
    while (isIdentifierChar(peek())) {
      ++current;
    }
    const StringRef word(start, current - start);
    if (word == "#pragma") {
      return makeToken(TokenKind::KwPragma, start);
    }
    if (word == "#dim") {
      return makeToken(TokenKind::KwDim, start);
    }
    return makeError(start, "unexpected '#'");
  }
  default:
    return makeError(start, "unexpected character");
  }
}

Token Lexer::lexIdentifierOrKeyword(const char* start) {
  while (isIdentifierChar(peek())) {
    ++current;
  }
  const StringRef word(start, current - start);
  const TokenKind kind = llvm::StringSwitch<TokenKind>(word)
                             .Case("OPENQASM", TokenKind::KwOpenQASM)
                             .Case("include", TokenKind::KwInclude)
                             .Case("defcalgrammar", TokenKind::KwDefcalgrammar)
                             .Case("def", TokenKind::KwDef)
                             .Case("cal", TokenKind::KwCal)
                             .Case("defcal", TokenKind::KwDefcal)
                             .Case("gate", TokenKind::KwGate)
                             .Case("extern", TokenKind::KwExtern)
                             .Case("box", TokenKind::KwBox)
                             .Case("let", TokenKind::KwLet)
                             .Case("break", TokenKind::KwBreak)
                             .Case("continue", TokenKind::KwContinue)
                             .Case("if", TokenKind::KwIf)
                             .Case("else", TokenKind::KwElse)
                             .Case("end", TokenKind::KwEnd)
                             .Case("return", TokenKind::KwReturn)
                             .Case("for", TokenKind::KwFor)
                             .Case("while", TokenKind::KwWhile)
                             .Case("in", TokenKind::KwIn)
                             .Case("switch", TokenKind::KwSwitch)
                             .Case("case", TokenKind::KwCase)
                             .Case("default", TokenKind::KwDefault)
                             .Case("nop", TokenKind::KwNop)
                             .Case("pragma", TokenKind::KwPragma)
                             .Case("input", TokenKind::KwInput)
                             .Case("output", TokenKind::KwOutput)
                             .Case("const", TokenKind::KwConst)
                             .Case("readonly", TokenKind::KwReadonly)
                             .Case("mutable", TokenKind::KwMutable)
                             .Case("qreg", TokenKind::KwQreg)
                             .Case("qubit", TokenKind::KwQubit)
                             .Case("creg", TokenKind::KwCreg)
                             .Case("bool", TokenKind::KwBool)
                             .Case("bit", TokenKind::KwBit)
                             .Case("int", TokenKind::KwInt)
                             .Case("uint", TokenKind::KwUint)
                             .Case("float", TokenKind::KwFloat)
                             .Case("angle", TokenKind::KwAngle)
                             .Case("complex", TokenKind::KwComplex)
                             .Case("array", TokenKind::KwArray)
                             .Case("void", TokenKind::KwVoid)
                             .Case("duration", TokenKind::KwDuration)
                             .Case("stretch", TokenKind::KwStretch)
                             .Case("gphase", TokenKind::KwGphase)
                             .Case("inv", TokenKind::KwInv)
                             .Case("pow", TokenKind::KwPow)
                             .Case("ctrl", TokenKind::KwCtrl)
                             .Case("negctrl", TokenKind::KwNegctrl)
                             .Case("durationof", TokenKind::KwDurationof)
                             .Case("delay", TokenKind::KwDelay)
                             .Case("reset", TokenKind::KwReset)
                             .Case("measure", TokenKind::KwMeasure)
                             .Case("barrier", TokenKind::KwBarrier)
                             .Case("true", TokenKind::KwTrue)
                             .Case("false", TokenKind::KwFalse)
                             .Default(TokenKind::Identifier);
  return makeToken(kind, start);
}

/// Consumes digits accepted by `isValidDigit`, separated by single underscores. Returns whether at least one digit was
/// consumed and the separators were well placed.
template <typename Pred> static bool consumeDigits(const char*& current, const char* end, Pred isValidDigit) {
  bool any = false;
  bool lastWasSeparator = false;
  while (current < end) {
    if (isValidDigit(*current)) {
      any = true;
      lastWasSeparator = false;
    } else if (*current == '_' && any && !lastWasSeparator) {
      lastWasSeparator = true;
    } else {
      break;
    }
    ++current;
  }
  return any && !lastWasSeparator;
}

Token Lexer::lexNumber(const char* start) {
  current = start;
  const char* end = buffer.end();
  auto isBinary = [](char c) { return c == '0' || c == '1'; };
  auto isOctal = [](char c) { return c >= '0' && c <= '7'; };
  auto isDecimal = [](char c) { return llvm::isDigit(c); };
  auto isHex = [](char c) { return llvm::isHexDigit(c); };

  TokenKind kind = TokenKind::IntegerLiteral;
  const char next = peek(1);
  if (peek() == '0' && (next == 'b' || next == 'B' || next == 'o' || next == 'x' || next == 'X')) {
    current += 2;
    const bool valid = (next == 'b' || next == 'B') ? consumeDigits(current, end, isBinary)
                       : next == 'o'                ? consumeDigits(current, end, isOctal)
                                                    : consumeDigits(current, end, isHex);
    if (!valid || isIdentifierChar(peek())) {
      while (isIdentifierChar(peek())) {
        ++current;
      }
      return makeError(start, "invalid integer literal");
    }
    return makeToken(kind, start);
  }

  // Decimal integer or float: digits, an optional fraction, and an optional exponent.
  bool valid = peek() == '.' || consumeDigits(current, end, isDecimal);
  if (valid && peek() == '.') {
    kind = TokenKind::FloatLiteral;
    ++current;
    if (llvm::isDigit(peek())) {
      valid = consumeDigits(current, end, isDecimal);
    } else {
      // `2.` is a float, but `.` alone is no number.
      valid = current - start > 1;
    }
  }
  if (valid && (peek() == 'e' || peek() == 'E')) {
    kind = TokenKind::FloatLiteral;
    ++current;
    if (peek() == '+' || peek() == '-') {
      ++current;
    }
    valid = consumeDigits(current, end, isDecimal);
  }
  if (!valid) {
    while (isIdentifierChar(peek())) {
      ++current;
    }
    return makeError(start, "invalid number");
  }

  // An imaginary or timing literal continues with its suffix, optionally after spaces.
  const char* afterNumber = current;
  while (peek() == ' ' || peek() == '\t') {
    ++current;
  }
  const char* suffixStart = current;
  while (isIdentifierChar(peek())) {
    ++current;
  }
  const StringRef suffix(suffixStart, current - suffixStart);
  if (suffix == "im") {
    return makeToken(TokenKind::ImaginaryLiteral, start);
  }
  if (suffix == "dt" || suffix == "ns" || suffix == "us" || suffix == "µs" || suffix == "ms" || suffix == "s") {
    return makeToken(TokenKind::TimingLiteral, start);
  }
  if (!suffix.empty() && suffixStart == afterNumber) {
    return makeError(start, "invalid number");
  }
  current = afterNumber;
  return makeToken(kind, start);
}

Token Lexer::lexString(const char* start) {
  const char quote = *start;
  while (!atEnd() && peek() != quote && peek() != '\n' && peek() != '\r') {
    ++current;
  }
  if (peek() != quote) {
    return makeError(start, "unterminated string");
  }
  ++current;
  return makeToken(TokenKind::StringLiteral, start);
}
