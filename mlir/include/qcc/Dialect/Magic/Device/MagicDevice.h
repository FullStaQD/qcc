// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#pragma once

#include "qcc/Dialect/Magic/IR/Magic.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include <cstdint>
#include <string>

namespace qcc::magic {

using TrapId = unsigned;
using IonCount = unsigned;
/// Integer multiples of the device's base time unit, the unit of `magic.delay`.
using Ticks = int64_t;

/// Coupling strengths of one chain of `n` ions: symmetric, zero diagonal, indexed by chain position (front = 0).
///
/// Unit: rad/s (TODO: to be confirmed by eleQtron).
class CouplingMatrix {
public:
  CouplingMatrix() = default;

  /// From an `n x n` `f64` matrix attribute as carried by `#magic.trap`.
  explicit CouplingMatrix(mlir::DenseElementsAttr matrix);

  /// The number of ions this matrix is for.
  [[nodiscard]] IonCount size() const { return numIons; }

  /// The coupling between the ions at chain positions `i` and `j`.
  [[nodiscard]] double operator()(unsigned i, unsigned j) const;

  /// An `n x n` `f64` tensor.
  [[nodiscard]] mlir::DenseElementsAttr toAttr(mlir::MLIRContext& ctx) const;

private:
  IonCount numIons = 0;
  llvm::SmallVector<double> data; // row-major n x n
};

/// Corresponds to `#magic.device` in IR.
///
/// TODO: construct from QDMI.
class MagicDevice {
public:
  /// From the `#magic.device` attr. Cannot fail: the attribute verifier already enforces same-length arrays, occupancy
  /// <= capacity, a positive time unit and a complete coupling table.
  static MagicDevice fromAttr(DeviceAttr attr);

  /// Looks up `qcc.device` on the module and checks that it is a `#magic.device`.
  static mlir::FailureOr<MagicDevice> fromModule(mlir::ModuleOp module);

  /// Parses a device file (see `qcc::parseDeviceFile`) that carries a `#magic.device`.
  static mlir::FailureOr<MagicDevice> fromFile(llvm::StringRef path, mlir::MLIRContext& ctx);

  /// To `#magic.device`.
  [[nodiscard]] DeviceAttr toAttr(mlir::MLIRContext& ctx) const;

  //===--------------------------------------------------------------------===//
  // Device data (read-only)
  //===--------------------------------------------------------------------===//

  [[nodiscard]] llvm::StringRef name() const { return deviceName; }
  [[nodiscard]] unsigned numTraps() const { return static_cast<unsigned>(traps.size()); }
  [[nodiscard]] IonCount capacity(TrapId trap) const;
  /// The number of ions loaded into `trap` at program start.
  [[nodiscard]] IonCount initialOccupancy(TrapId trap) const;
  /// The number of ions on the device, i.e. the sum of the initial occupancies.
  [[nodiscard]] IonCount numIons() const;

  /// The base unit of `magic.delay` in nanoseconds.
  [[nodiscard]] int64_t timeUnitNs() const { return timeUnit; }
  /// Exact conversion, for the exporter (`delay[<t>us]`).
  [[nodiscard]] double ticksToMicroseconds(Ticks ticks) const;
  /// Rounds to the nearest tick.
  [[nodiscard]] Ticks microsecondsToTicks(double microseconds) const;

  /// The coupling matrix of `trap` with `n` ions present (active and inactive), `1 <= n <= capacity(trap)`. Callers
  /// restrict it to the active positions themselves.
  [[nodiscard]] const CouplingMatrix& coupling(TrapId trap, IonCount n) const;

private:
  MagicDevice() = default;

  struct Trap {
    IonCount capacity = 0;
    llvm::SmallVector<CouplingMatrix> couplings; // index n-1: the matrix for n ions present
  };

  std::string deviceName;
  int64_t timeUnit = 0;
  llvm::SmallVector<IonCount> occupancies;
  llvm::SmallVector<Trap> traps;
};

} // namespace qcc::magic
