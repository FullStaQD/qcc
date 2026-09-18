// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Compiler/Protocol.h"

#include "qcc/Constants.h"
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Location.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/JSON.h"

using namespace mlir;

namespace {

/// A position in a frontend source file, as a diagnostic record carries it.
struct SourcePos {
  StringRef file;
  unsigned line;
  unsigned column;
};

/// The position a diagnostic at `loc` is reported at, plus the callers that
/// led to it.
///
/// A location is a tree rather than a position: Mojo names an inlined call
/// with a `callsite`, and the passes fuse locations as they rewrite. The
/// innermost `FileLineColLoc` is what the caller should point its user at,
/// and the callers above it are what explains how the program got there, so
/// they come back as a separate list to be reported as notes.
std::optional<SourcePos> findPosition(Location loc, SmallVectorImpl<SourcePos>& callers) {
  if (auto fileLoc = dyn_cast<FileLineColLoc>(loc)) {
    return SourcePos{fileLoc.getFilename().getValue(), fileLoc.getLine(), fileLoc.getColumn()};
  }
  if (auto callSiteLoc = dyn_cast<CallSiteLoc>(loc)) {
    std::optional<SourcePos> callee = findPosition(callSiteLoc.getCallee(), callers);
    // The caller's own callsite chain is a chain of callers too, so it is
    // flattened into the same list rather than nested.
    SmallVector<SourcePos> callerCallers;
    if (std::optional<SourcePos> caller = findPosition(callSiteLoc.getCaller(), callerCallers)) {
      callers.push_back(*caller);
    }
    llvm::append_range(callers, callerCallers);
    return callee;
  }
  if (auto nameLoc = dyn_cast<NameLoc>(loc)) {
    return findPosition(nameLoc.getChildLoc(), callers);
  }
  if (auto opaqueLoc = dyn_cast<OpaqueLoc>(loc)) {
    return findPosition(opaqueLoc.getFallbackLocation(), callers);
  }
  if (auto fusedLoc = dyn_cast<FusedLoc>(loc)) {
    for (Location nested : fusedLoc.getLocations()) {
      if (std::optional<SourcePos> position = findPosition(nested, callers)) {
        return position;
      }
    }
  }
  return std::nullopt;
}

/// The attribute `mojo-residue-to-std` marks a haloed function with.
constexpr llvm::StringLiteral kHaloAttrName = "prelimhlep.halo";

/// Writes an array of printed types, leaving out the halo unit.
///
/// `!prelimhlep.unit` is qcc's own token: the halo verifier wants a haloed
/// function to name the state it acts on, and the residue translation
/// synthesizes one for a kernel that takes no classical arguments. The caller
/// never wrote it and has no value to pass for it, so the signature it types
/// its launcher from must not mention it. That the kernel is haloed is said
/// once, by the `halo` field, instead.
void writeTypes(llvm::json::OStream& json, llvm::StringRef field, TypeRange types) {
  json.attributeArray(field, [&] {
    for (Type type : types) {
      if (isa<qcc::prelimhlep::UnitType>(type)) {
        continue;
      }
      std::string printed;
      llvm::raw_string_ostream stream(printed);
      type.print(stream);
      json.value(printed);
    }
  });
}

/// The `severity` field's spelling.
StringRef severityName(DiagnosticSeverity severity) {
  switch (severity) {
  case DiagnosticSeverity::Note:
    return "note";
  case DiagnosticSeverity::Warning:
    return "warning";
  case DiagnosticSeverity::Error:
    return "error";
  case DiagnosticSeverity::Remark:
    return "remark";
  }
  llvm_unreachable("unknown diagnostic severity");
}

/// Writes the `file`/`line`/`column` fields of a record, if the location has
/// them. A location qcc cannot resolve leaves them out rather than inventing
/// a position, so a caller can tell "somewhere in this kernel" from "line 12".
void writePosition(llvm::json::OStream& json, const std::optional<SourcePos>& position) {
  if (!position) {
    return;
  }
  json.attribute("file", position->file);
  json.attribute("line", position->line);
  json.attribute("column", position->column);
}

void writeNote(llvm::json::OStream& json, StringRef severity, StringRef message, const std::optional<SourcePos>& pos) {
  json.object([&] {
    json.attribute("severity", severity);
    json.attribute("message", message);
    writePosition(json, pos);
  });
}

/// Writes one diagnostic as a single JSON line.
void writeDiagnostic(llvm::raw_ostream& os, Diagnostic& diagnostic) {
  SmallVector<SourcePos> callers;
  std::optional<SourcePos> position = findPosition(diagnostic.getLocation(), callers);

  llvm::json::OStream json(os);
  json.object([&] {
    json.attribute("severity", severityName(diagnostic.getSeverity()));
    json.attribute("message", diagnostic.str());
    writePosition(json, position);

    if (callers.empty() && diagnostic.getNotes().empty()) {
      return;
    }
    json.attributeArray("notes", [&] {
      for (const SourcePos& caller : callers) {
        writeNote(json, "note", "called from here", caller);
      }
      for (Diagnostic& note : diagnostic.getNotes()) {
        // A note's own callers are discarded: a note usually sits at the same
        // location as the diagnostic it belongs to, so expanding its chain as
        // well repeats the callers that were just written. The text handler
        // reports notes at their position alone for the same reason.
        SmallVector<SourcePos> noteCallers;
        std::optional<SourcePos> notePosition = findPosition(note.getLocation(), noteCallers);
        writeNote(json, severityName(note.getSeverity()), note.str(), notePosition);
      }
    });
  });
  os << "\n";
  // A caller relays diagnostics while qcc is still running, so a record is of
  // no use to it until it has been written out.
  os.flush();
}

} // namespace

namespace qcc {

JsonDiagnosticHandler::JsonDiagnosticHandler(MLIRContext* context, llvm::raw_ostream& os)
    : ScopedDiagnosticHandler(context) {
  setHandler([&os](Diagnostic& diagnostic) {
    writeDiagnostic(os, diagnostic);
    return success();
  });
}

void writeEntryPointSidecar(ModuleOp module, llvm::raw_ostream& os) {
  llvm::json::OStream json(os, /*IndentSize=*/2);
  json.object([&] {
    json.attribute("protocol", static_cast<int64_t>(currentProtocolVersion));
    json.attributeArray("entry_points", [&] {
      module.walk([&](func::FuncOp func) {
        if (!func->hasAttr(qcc::entryPointAttrName)) {
          return;
        }
        json.object([&] {
          json.attribute("name", func.getName());
          json.attribute("halo", func->hasAttr(kHaloAttrName));
          FunctionType type = func.getFunctionType();
          writeTypes(json, "arguments", type.getInputs());
          writeTypes(json, "results", type.getResults());
        });
      });
    });
  });
  os << "\n";
}

} // namespace qcc
