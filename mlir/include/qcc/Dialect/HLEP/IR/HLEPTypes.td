// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_HLEP_IR_HLEPTYPES_TD_
#define INCLUDE_QCC_DIALECT_HLEP_IR_HLEPTYPES_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"
include "HLEPDialect.td"


//===----------------------------------------------------------------------===//
// HLEP types
//===----------------------------------------------------------------------===//

class HLEPType<string name, string typeMnemonic>
    : TypeDef<HLEPDialect, name> {
    let mnemonic = typeMnemonic;
}

def LinType : HLEPType<"Lin", "lin"> {
    let summary = "The linearization of a hybrid type.";
    let description = [{
        `!hlep.lin<T>` is the purely-linear (quantum) type obtained by
        linearizing the hybrid type `T`, i.e. Lin[T]. Values of this type
        behave as quantum values with a single use (see the `LinearHalo` function
        attribute).

        TODO: This functor is idempotent. See if this can be incorporated.
    }];

    let parameters = (ins "::mlir::Type":$elementType);
    let assemblyFormat = "`<` $elementType `>`";
}

def UnitType : HLEPType<"Unit", "unit"> {
    let summary = "In linear context, the tensor unit of the linear product.";
    let description = [{
        Semantically identical to `none` type, but safe against accidental deletion
        from function signatures.
        Classical unit in classical context, linear unit in linear context.

        `LinearHalo`-attributed functions must take/return this type instead
        of having zero arguments/results.
    }];
}

def XType : HLEPType<"X", "x"> {
    let summary = "Classical type for length-n strings over the X-basis symbols {+, -}.";
    let description = [{
        `!hlep.x<n>` is a purely classical type whose terms are
        length-`n` strings of the symbols `+` and `-`. It carries the same
        classical information content as `i<n>`, but its linearization
        `!hlep.lin<!hlep.x<n>>` is identified -- via
        `hlep.base_change` -- with the same vector space as
        `!hlep.lin<i<n>>`, equipped with the X-basis instead of the
        computational (Z) basis.

        TODO: decide representation/verification for `n` (e.g. non-negative).
    }];

    let parameters = (ins "int64_t":$size);
    let assemblyFormat = "`<` $size `>`";
}

def YType : HLEPType<"Y", "y"> {
    let summary = "Classical type for length-n strings over the Y-basis symbols {>, <}.";
    let description = [{
        `!hlep.y<n>` is a purely classical type whose terms are
        length-`n` strings of the symbols `>` and `<` (the tips of the arrows
        `->` and `<-`). Analogous to
        `!hlep.x<n>`, but for the Y-basis. See `XType` above.

        TODO: decide representation/verification for `n` (e.g. non-negative).
    }];

    let parameters = (ins "int64_t":$size);
    let assemblyFormat = "`<` $size `>`";
}

#endif // INCLUDE_QCC_DIALECT_HLEP_IR_HLEPTYPES_TD_
