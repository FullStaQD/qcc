// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICTYPES_TD_
#define INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICTYPES_TD_

include "qcc/Dialect/Magic/IR/MagicDialect.td"

include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// Magic types
//===----------------------------------------------------------------------===//

class Magic_Type<string name, string typeMnemonic, list<Trait> traits = []> : TypeDef<Magic_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

def Magic_IonChainType : Magic_Type<"IonChain", "ion_chain"> {
  let summary = "the ions of one trap, front to back, with their activation";
  let description = [{
        `!magic.ion_chain<trap, [ion:active, ...]>` is the state of one trap: the trap id and the ions it holds, listed
        front to back (position 0 first). Each entry is the ion *id* and its activation (`1` active, `0` inactive).

        Example: trap 0 holds ions 2, 3 and 0 at positions 0, 1 and 2; ion 0 is inactive.
        ```mlir
        !magic.ion_chain<0, [2:1, 3:1, 0:0]>
        ```

        Ion ids are distinct and non-negative. The empty chain is a valid type.
    }];

  let parameters = (ins
    "int64_t":$trap,
    ArrayRefParameter<"::qcc::magic::IonSlot", "ions front to back">:$slots
  );

  let hasCustomAssemblyFormat = 1;
  let genVerifyDecl = 1;

  let extraClassDeclaration = [{
        /// The number of ions in the chain, active or not.
        unsigned getNumIons() const { return static_cast<unsigned>(getSlots().size()); }

        /// Whether the chain holds the ion with id `ion`.
        bool contains(int64_t ion) const;

        /// The ion ids in position order (front = 0).
        ::llvm::SmallVector<int64_t> getIons() const;

        /// The position of `ion` (front = 0). Asserts that the chain contains `ion`.
        unsigned getPosition(int64_t ion) const;

        /// Whether `ion` is active. Asserts that the chain contains `ion`.
        bool isActive(int64_t ion) const;

        /// The ids of the active ions in position order.
        ::llvm::SmallVector<int64_t> getActiveIons() const;

        /// The positions of the active ions, ascending.
        ::llvm::SmallVector<unsigned> getActivePositions() const;

        /// The number of active ions.
        unsigned getNumActiveIons() const { return static_cast<unsigned>(getActivePositions().size()); }

        /// The same chain with the activation of every ion in `ions` toggled. Asserts that the chain contains them.
        IonChainType withToggled(::llvm::ArrayRef<int64_t> ions) const;

        /// The same chain without its front ion. Asserts that the chain is not empty.
        IonChainType withoutFront() const;

        /// The same chain with `ion` inserted at the front. Asserts that the chain does not contain `ion` yet.
        IonChainType withFront(int64_t ion, bool active) const;
    }];
}

#endif // INCLUDE_QCC_DIALECT_MAGIC_IR_MAGICTYPES_TD_
