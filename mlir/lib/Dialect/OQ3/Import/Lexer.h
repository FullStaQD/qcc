// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/SMLoc.h"

#include <cstdint>
#include <optional>
#include <vector>

namespace qcc::oq3::detail {

enum class TokenKind : uint8_t {
  Eof,
  Error, // The spelling is the offending text, `Token::message` says what is wrong.

  Identifier,
  HardwareQubit,    // $3
  Annotation,       // @ns.name, without the rest of the line
  IntegerLiteral,   // 0b101, 0o17, 15, 0x1F
  FloatLiteral,     // 1.5e3, .5, 2.
  ImaginaryLiteral, // 2.5im
  TimingLiteral,    // 100ns
  StringLiteral,    // "..." or '...', also bitstrings

  // Punctuation and operators.
  LBracket,
  RBracket,
  LBrace,
  RBrace,
  LParen,
  RParen,
  Colon,
  Semicolon,
  Dot,
  Comma,
  Equals,
  Arrow,
  Plus,
  DoublePlus,
  Minus,
  Asterisk,
  DoubleAsterisk,
  Slash,
  Percent,
  Pipe,
  DoublePipe,
  Ampersand,
  DoubleAmpersand,
  Caret,
  At,
  Tilde,
  Exclamation,
  EqualEqual,
  NotEqual,
  Less,
  LessEqual,
  Greater,
  GreaterEqual,
  ShiftLeft,
  ShiftRight,
  CompoundAssign, // += -= *= /= %= **= &= |= ^= <<= >>=

  // Keywords.
  KwOpenQASM,
  KwInclude,
  KwDefcalgrammar,
  KwDef,
  KwCal,
  KwDefcal,
  KwGate,
  KwExtern,
  KwBox,
  KwLet,
  KwBreak,
  KwContinue,
  KwIf,
  KwElse,
  KwEnd,
  KwReturn,
  KwFor,
  KwWhile,
  KwIn,
  KwSwitch,
  KwCase,
  KwDefault,
  KwNop,
  KwPragma, // pragma or #pragma
  KwInput,
  KwOutput,
  KwConst,
  KwReadonly,
  KwMutable,
  KwQreg,
  KwQubit,
  KwCreg,
  KwBool,
  KwBit,
  KwInt,
  KwUint,
  KwFloat,
  KwAngle,
  KwComplex,
  KwArray,
  KwVoid,
  KwDuration,
  KwStretch,
  KwGphase,
  KwInv,
  KwPow,
  KwCtrl,
  KwNegctrl,
  KwDim, // #dim
  KwDurationof,
  KwDelay,
  KwReset,
  KwMeasure,
  KwBarrier,
  KwTrue,
  KwFalse,
};

struct Token {
  TokenKind kind = TokenKind::Eof;
  llvm::StringRef spelling;
  /// For an `Error` token: what is wrong.
  llvm::StringRef message;

  bool is(TokenKind other) const { return kind == other; }
  llvm::SMLoc getLoc() const { return llvm::SMLoc::getFromPointer(spelling.data()); }
  llvm::SMLoc getEndLoc() const { return llvm::SMLoc::getFromPointer(spelling.data() + spelling.size()); }
};

/// Splits OpenQASM 3 source text into tokens. Comments are no tokens; the lexer collects them instead, so that the
/// parser can turn them into IR.
class Lexer {
public:
  explicit Lexer(llvm::StringRef buffer) : buffer(buffer), current(buffer.begin()) {}

  Token lex();

  /// Returns the rest of the current line, without leading whitespace and without the line break, and continues
  /// after it. Used for pragmas and annotations, which extend to the end of the line.
  llvm::StringRef lexRestOfLine();

  /// The comments lexed since the last call, in source order.
  std::vector<llvm::StringRef> takeComments() { return std::move(comments); }

  /// The text of the whole buffer.
  llvm::StringRef getBuffer() const { return buffer; }

private:
  Token makeToken(TokenKind kind, const char* start) const {
    return Token{.kind = kind, .spelling = llvm::StringRef(start, current - start)};
  }
  Token makeError(const char* start, llvm::StringRef message) const {
    return Token{.kind = TokenKind::Error, .spelling = llvm::StringRef(start, current - start), .message = message};
  }
  bool atEnd() const { return current == buffer.end(); }
  char peek(size_t offset = 0) const { return current + offset < buffer.end() ? current[offset] : '\0'; }

  /// Skips whitespace and comments. Returns an error token for an unterminated block comment.
  std::optional<Token> skipWhitespaceAndComments();
  Token lexIdentifierOrKeyword(const char* start);
  Token lexNumber(const char* start);
  Token lexString(const char* start);

  llvm::StringRef buffer;
  const char* current;
  std::vector<llvm::StringRef> comments;
};

/// Whether `c` may start an identifier. All non-ASCII bytes are accepted, which covers Unicode letters like `π`.
inline bool isIdentifierStart(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || static_cast<unsigned char>(c) >= 0x80;
}

/// Whether `c` may continue an identifier.
inline bool isIdentifierChar(char c) { return isIdentifierStart(c) || (c >= '0' && c <= '9'); }

} // namespace qcc::oq3::detail
