// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/Export/Export.h"

#include "qcc/Dialect/Aux_/IR/Aux_.h"
#include "qcc/Dialect/Magic/Device/MagicDevice.h"
#include "qcc/Dialect/Magic/IR/Magic.h"
#include "qcc/Dialect/QVec/Transforms/ZXZ.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/raw_ostream.h"

#include <array>
#include <cassert>
#include <charconv>
#include <cstdint>
#include <iterator>
#include <memory>
#include <string>
#include <system_error>

using namespace mlir;
using qcc::qvec::normalizeAngle;

namespace qcc::magic {

/// Header line required by the target format.
static constexpr llvm::StringLiteral nativeGatesInclude = "include \"qsea_native_gates.inc\";";

/// `value` as a plain decimal: the shortest one that reads back as the same value, never in scientific notation.
static std::string toDecimal(double value) {
  // Long enough for every double in fixed notation.
  std::array<char, 512> buffer{};
  const std::to_chars_result result =
      std::to_chars(buffer.data(), std::to_address(buffer.end()), value, std::chars_format::fixed);
  assert(result.ec == std::errc() && "buffer too small for a double");
  return {buffer.data(), result.ptr};
}

/// An ion as the format names it: the ion id is the index into the quantum register.
static std::string toQubit(int64_t ion) { return ("q[" + Twine(ion) + "]").str(); }

namespace {

/// Translates one program. The statements are collected first, since the header describes what the walk finds.
class Exporter {
public:
  Exporter(InitOp init, const MagicDevice& device) : init(init), device(device), body(bodyText) {}

  LogicalResult run(raw_ostream& os) {
    if (failed(readInitialOccupancies())) {
      return failure();
    }
    for (Operation& op : *init->getBlock()) {
      if (failed(exportOp(&op))) {
        return failure();
      }
    }
    if (failed(checkAllRecorded())) {
      return failure();
    }

    printHeader(os);
    os << bodyText;
    for (int64_t ion = 0; ion < numIons(); ++ion) {
      os << "c[" << bitOfIon[ion] << "] = measure " << toQubit(ion) << ";\n";
    }
    return success();
  }

private:
  [[nodiscard]] int64_t numIons() const { return std::ssize(bitOfIon); }

  /// The ions each trap holds initially. The format has no ion ids of its own: ion `i` is the `i`-th qubit, counted
  /// trap by trap.
  LogicalResult readInitialOccupancies() {
    occupancies.assign(device.numTraps(), 0);
    int64_t expected = 0;
    for (Value value : init.getChains()) {
      auto chain = cast<IonChainType>(value.getType());
      if (chain.getTrap() >= device.numTraps()) {
        return init.emitOpError() << "loads trap " << chain.getTrap() << ", but the device has " << device.numTraps()
                                  << " traps";
      }
      occupancies[chain.getTrap()] = chain.getNumIons();
      for (const int64_t ion : chain.getIons()) {
        if (ion != expected) {
          return init.emitOpError() << "cannot be exported: found ion " << ion << " where the format expects ion "
                                    << expected << ", the ions are numbered 0..N-1 trap by trap";
        }
        ++expected;
      }
    }
    bitOfIon.assign(expected, unrecorded);
    return success();
  }

  LogicalResult exportOp(Operation* op) {
    // A chain nobody consumes is a chain nobody measures.
    for (Value result : op->getResults()) {
      auto chain = dyn_cast<IonChainType>(result.getType());
      if (chain && result.use_empty() && chain.getNumIons() > 0) {
        return op->emitOpError() << "cannot be exported: the chain " << chain
                                 << " it produces is never measured, but the format measures every ion";
      }
    }

    return llvm::TypeSwitch<Operation*, LogicalResult>(op)
        .Case([&](RZOp rz) { return exportRZ(rz); })
        .Case([&](SymZXZOp sym) { return exportSymZXZ(sym); })
        .Case([&](DelayOp delay) { return exportDelay(delay); })
        .Case([&](RecodeOp recode) { return exportRecode(recode); })
        .Case([&](ShuttleOp shuttle) { return exportShuttle(shuttle); })
        .Case([&](aux::RecordIntOp record) { return exportRecord(record); })
        .Case([&](MZDOp mzd) { return exportMZD(mzd); })
        .Case([](InitOp) { return success(); })
        .Case([&](func::ReturnOp ret) -> LogicalResult {
          if (ret.getNumOperands() != 0) {
            return ret.emitOpError() << "cannot be exported: a program returns nothing, it records its results";
          }
          return success();
        })
        .Default([](Operation* other) -> LogicalResult {
          if (isa_and_present<MagicDialect>(other->getDialect())) {
            return other->emitOpError() << "cannot be exported: it is not native to the device";
          }
          return other->emitOpError() << "cannot be exported: the format has native magic ops and records only";
        });
  }

  LogicalResult exportRZ(RZOp rz) {
    for (auto [ion, angle] : llvm::zip_equal(rz.getIons(), rz.getAngles().getAsValueRange<FloatAttr>())) {
      body << "rz(" << toDecimal(normalizeAngle(angle.convertToDouble())) << ") " << toQubit(ion) << ";\n";
    }
    return success();
  }

  /// One instruction for the device, three lines in the format: rz(z), rx(x), rz(-z).
  LogicalResult exportSymZXZ(SymZXZOp sym) {
    for (auto [ion, zAttr, xAttr] : llvm::zip_equal(sym.getIons(), sym.getZ().getAsValueRange<FloatAttr>(),
                                                    sym.getX().getAsValueRange<FloatAttr>())) {
      const double z = normalizeAngle(zAttr.convertToDouble());
      const double x = normalizeAngle(xAttr.convertToDouble());
      // The third angle is the negation of the first as it is printed. No "-0".
      const double minusZ = z == 0.0 ? 0.0 : -z;
      body << "rz(" << toDecimal(z) << ") " << toQubit(ion) << ";\n";
      body << "rx(" << toDecimal(x) << ") " << toQubit(ion) << ";\n";
      body << "rz(" << toDecimal(minusZ) << ") " << toQubit(ion) << ";\n";
    }
    return success();
  }

  /// A delay names all ions of its trap, active or not, front to back.
  LogicalResult exportDelay(DelayOp delay) {
    const IonChainType chain = delay.getChainIn().getType();
    const std::string microseconds = toDecimal(device.ticksToMicroseconds(static_cast<Ticks>(delay.getTicks())));
    if (chain.getNumIons() == 0) {
      // An empty trap waits as well (see `magic-pad-timing`), but the format has no statement without qubits.
      body << "// delay[" << microseconds << "us] <empty trap " << chain.getTrap() << ">\n";
      return success();
    }
    body << "delay[" << microseconds << "us] ";
    llvm::interleave(chain.getIons(), body, [&](int64_t ion) { body << toQubit(ion); }, ",");
    body << ";\n";
    return success();
  }

  LogicalResult exportRecode(RecodeOp recode) {
    for (auto [before, after] :
         llvm::zip_equal(recode.getChainIn().getType().getSlots(), recode.getChainOut().getType().getSlots())) {
      if (before.active != after.active) {
        body << "recode " << toQubit(before.ion) << ";\n";
      }
    }
    return success();
  }

  LogicalResult exportShuttle(ShuttleOp shuttle) {
    body << "shuttle(" << shuttle.getFromIn().getType().getTrap() << "," << shuttle.getToIn().getType().getTrap()
         << ") " << toQubit(shuttle.getMovedIon()) << ";\n";
    return success();
  }

  /// The measurements themselves are printed at the end, in ion order.
  static LogicalResult exportMZD(MZDOp mzd) {
    for (auto [ion, bit] : llvm::zip_equal(mzd.getChain().getType().getIons(), mzd.getBits())) {
      if (bit.use_empty()) {
        return mzd.emitOpError() << "cannot be exported: its result for ion " << ion
                                 << " is not recorded, but the format reports every ion";
      }
    }
    return success();
  }

  /// The `j`-th record of the program is the classical bit `c[j]`.
  LogicalResult exportRecord(aux::RecordIntOp record) {
    auto bit = dyn_cast<OpResult>(record.getValue());
    auto mzd = bit ? dyn_cast<MZDOp>(bit.getOwner()) : MZDOp();
    if (!mzd) {
      return record.emitOpError() << "cannot be exported: it records a value that is not a 'magic.mzd' result";
    }
    const int64_t ion = mzd.getChain().getType().getIons()[bit.getResultNumber()];
    if (bitOfIon[ion] != unrecorded) {
      return record.emitOpError() << "cannot be exported: the result for ion " << ion << " is recorded twice";
    }
    bitOfIon[ion] = numRecords++;

    if (MagicDialect::GarbageResultAttrHelper(record->getContext()).isAttrPresent(record)) {
      return success();
    }
    if (numRecords - 1 != numProgramBits) {
      return record.emitOpError() << "cannot be exported: it records a result of the program after a garbage result";
    }
    ++numProgramBits;
    return success();
  }

  /// The format assigns a classical bit to every ion. What the walk has not rejected yet: a result that is used, but
  /// not by a record of the program.
  LogicalResult checkAllRecorded() {
    for (int64_t ion = 0; ion < numIons(); ++ion) {
      if (bitOfIon[ion] == unrecorded) {
        return init.emitOpError() << "cannot be exported: the program does not record the measurement result of ion "
                                  << ion << ", but the format reports every ion";
      }
    }
    return success();
  }

  void printHeader(raw_ostream& os) const {
    SmallVector<int64_t> capacities;
    for (TrapId trap = 0; trap < device.numTraps(); ++trap) {
      capacities.push_back(device.capacity(trap));
    }

    os << "OPENQASM 3.0;\n" << nativeGatesInclude << "\n\n";
    os << "// The program is compiled for " << device.numTraps() << " ion traps with the following configuration:\n";
    os << "//     capacities (";
    llvm::interleaveComma(capacities, os);
    os << "),\n//     occupancies (";
    llvm::interleaveComma(occupancies, os);
    os << "),\n//     ion-bit map [";
    llvm::interleaveComma(bitOfIon, os);
    os << "],\n//     unused_qubits ().\n";
    os << "// Result bits of the program: the first " << numProgramBits << " of c, the remaining bits are garbage.\n\n";
    os << "creg c[" << numIons() << "];\n";
    os << "qreg q[" << numIons() << "];\n";
  }

  static constexpr int64_t unrecorded = -1;

  InitOp init;
  const MagicDevice& device;

  /// Per trap of the device the number of ions it holds initially.
  SmallVector<int64_t> occupancies;
  /// Per ion the index of the record of its measurement.
  SmallVector<int64_t> bitOfIon;
  int64_t numRecords = 0;
  /// The records without `magic.garbage_result`. They come first.
  int64_t numProgramBits = 0;

  std::string bodyText;
  llvm::raw_string_ostream body;
};

} // namespace

LogicalResult exportProgram(ModuleOp module, raw_ostream& os) {
  // A program is a function with a `magic.init`.
  InitOp init;
  bool unique = true;
  module.walk([&](InitOp op) {
    if (!init) {
      init = op;
      return;
    }
    op.emitOpError()
        .append("starts a second program: only a module with a single program can be exported")
        .attachNote(init.getLoc())
        .append("the first program starts here");
    unique = false;
  });
  if (!unique) {
    return failure();
  }
  if (!init) {
    return module.emitError() << "module holds no program to export: expected a function with a 'magic.init'";
  }

  const FailureOr<MagicDevice> device = MagicDevice::fromModule(module);
  if (failed(device)) {
    return failure();
  }
  return Exporter(init, *device).run(os);
}

} // namespace qcc::magic
