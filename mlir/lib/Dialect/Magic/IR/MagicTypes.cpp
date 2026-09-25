// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Dialect/Magic/IR/Magic.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectImplementation.h" // IWYU pragma: keep
#include "mlir/IR/OpImplementation.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h" // IWYU pragma: keep
#include "llvm/Support/SMLoc.h"

#include <cassert>
#include <cstdint>

using namespace mlir;
using namespace qcc::magic;

#define GET_TYPEDEF_CLASSES
#include "qcc/Dialect/Magic/IR/MagicTypes.cpp.inc"

//===----------------------------------------------------------------------===//
// Registration
//===----------------------------------------------------------------------===//

// Lives here, next to the storage class the type definitions bring along.
void MagicDialect::registerTypes() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "qcc/Dialect/Magic/IR/MagicTypes.cpp.inc"
      >();
}

//===----------------------------------------------------------------------===//
// IonChainType: assembly
//===----------------------------------------------------------------------===//

// !magic.ion_chain<trap, [ion:active, ...]>
Type IonChainType::parse(AsmParser& parser) {
  const llvm::SMLoc loc = parser.getCurrentLocation();

  int64_t trap = 0;
  if (parser.parseLess() || parser.parseInteger(trap) || parser.parseComma()) {
    return {};
  }

  SmallVector<IonSlot> slots;
  auto parseSlot = [&]() -> ParseResult {
    IonSlot slot{};
    int64_t active = 0;
    const llvm::SMLoc activeLoc = parser.getCurrentLocation();
    if (parser.parseInteger(slot.ion) || parser.parseColon() || parser.parseInteger(active)) {
      return failure();
    }
    if (active != 0 && active != 1) {
      return parser.emitError(activeLoc, "expected activation 0 or 1, got ") << active;
    }
    slot.active = active == 1;
    slots.push_back(slot);
    return success();
  };
  if (parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, parseSlot) || parser.parseGreater()) {
    return {};
  }

  return getChecked([&] { return parser.emitError(loc); }, parser.getContext(), trap, slots);
}

void IonChainType::print(AsmPrinter& printer) const {
  printer << "<" << getTrap() << ", [";
  llvm::interleaveComma(getSlots(), printer,
                        [&](const IonSlot& slot) { printer << slot.ion << ":" << (slot.active ? 1 : 0); });
  printer << "]>";
}

//===----------------------------------------------------------------------===//
// IonChainType: verifier
//===----------------------------------------------------------------------===//

LogicalResult IonChainType::verify(function_ref<InFlightDiagnostic()> emitError, int64_t trap,
                                   ArrayRef<IonSlot> slots) {
  if (trap < 0) {
    return emitError() << "trap id must be non-negative, got " << trap;
  }

  llvm::SmallSet<int64_t, 8> seen;
  for (const IonSlot& slot : slots) {
    if (slot.ion < 0) {
      return emitError() << "ion id must be non-negative, got " << slot.ion;
    }
    if (!seen.insert(slot.ion).second) {
      return emitError() << "ion " << slot.ion << " appears more than once";
    }
  }
  return success();
}

//===----------------------------------------------------------------------===//
// IonChainType: helpers
//===----------------------------------------------------------------------===//

bool IonChainType::contains(int64_t ion) const {
  return llvm::any_of(getSlots(), [ion](const IonSlot& slot) { return slot.ion == ion; });
}

SmallVector<int64_t> IonChainType::getIons() const {
  return llvm::map_to_vector(getSlots(), [](const IonSlot& slot) { return slot.ion; });
}

unsigned IonChainType::getPosition(int64_t ion) const {
  const auto* it = llvm::find_if(getSlots(), [ion](const IonSlot& slot) { return slot.ion == ion; });
  assert(it != getSlots().end() && "ion is not in the chain");
  return static_cast<unsigned>(it - getSlots().begin());
}

bool IonChainType::isActive(int64_t ion) const { return getSlots()[getPosition(ion)].active; }

SmallVector<int64_t> IonChainType::getActiveIons() const {
  SmallVector<int64_t> ions;
  for (const IonSlot& slot : getSlots()) {
    if (slot.active) {
      ions.push_back(slot.ion);
    }
  }
  return ions;
}

SmallVector<unsigned> IonChainType::getActivePositions() const {
  SmallVector<unsigned> positions;
  for (auto [position, slot] : llvm::enumerate(getSlots())) {
    if (slot.active) {
      positions.push_back(static_cast<unsigned>(position));
    }
  }
  return positions;
}

IonChainType IonChainType::withToggled(ArrayRef<int64_t> ions) const {
  SmallVector<IonSlot> slots(getSlots());
  for (const int64_t ion : ions) {
    IonSlot& slot = slots[getPosition(ion)];
    slot.active = !slot.active;
  }
  return IonChainType::get(getContext(), getTrap(), slots);
}

IonChainType IonChainType::withoutFront() const {
  assert(getNumIons() > 0 && "chain is empty");
  return IonChainType::get(getContext(), getTrap(), getSlots().drop_front());
}

IonChainType IonChainType::withFront(int64_t ion, bool active) const {
  assert(!contains(ion) && "ion is already in the chain");
  SmallVector<IonSlot> slots;
  slots.reserve(getNumIons() + 1);
  slots.push_back(IonSlot{.ion = ion, .active = active});
  slots.append(getSlots().begin(), getSlots().end());
  return IonChainType::get(getContext(), getTrap(), slots);
}
