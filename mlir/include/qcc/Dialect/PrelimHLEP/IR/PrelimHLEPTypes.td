#ifndef INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPTYPES_TD_
#define INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPTYPES_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"
include "PrelimHLEPDialect.td"


//===----------------------------------------------------------------------===//
// PrelimHLEP types
//===----------------------------------------------------------------------===//

class PrelimHLEPType<string name, string typeMnemonic>
    : TypeDef<PrelimHLEPDialect, name> {
    let mnemonic = typeMnemonic;
}

def LinType : PrelimHLEPType<"Lin", "lin"> {
    let summary = "The linearization of a hybrid type.";
    let description = [{
        `!prelim_hlep.lin<T>` is the purely-linear (quantum) type obtained by
        linearizing the hybrid type `T`, i.e. Lin[T]. Values of this type
        behave as quantum values with a single use (see the `LinearHalo` function
        attribute).

        TODO: This functor is idempotent. See if this can be incorporated.
    }];

    let parameters = (ins "::mlir::Type":$elementType);
    let assemblyFormat = "`<` $elementType `>`";
}

def UnitType : PrelimHLEPType<"Unit", "unit"> {
    let summary = "In linear context, the tensor unit of the linear product.";
    let description = [{
        Semantically identical to `none` type, but safe against accidental deletion
        from function signatures.
        Classical unit in classical context, linear unit in linear context.

        `LinearHalo`-attributed functions must take/return this type instead
        of having zero arguments/results.
    }];
}

def XType : PrelimHLEPType<"X", "x"> {
    let summary = "Classical type for length-n strings over the X-basis symbols {+, -}.";
    let description = [{
        `!prelim_hlep.x<n>` is a purely classical type whose terms are
        length-`n` strings of the symbols `+` and `-`. It carries the same
        classical information content as `i<n>`, but its linearization
        `!prelim_hlep.lin<!prelim_hlep.x<n>>` is identified -- via
        `prelim_hlep.base_change` -- with the same vector space as
        `!prelim_hlep.lin<i<n>>`, equipped with the X-basis instead of the
        computational (Z) basis.

        TODO: decide representation/verification for `n` (e.g. non-negative).
    }];

    let parameters = (ins "int64_t":$size);
    let assemblyFormat = "`<` $size `>`";
}

def YType : PrelimHLEPType<"Y", "y"> {
    let summary = "Classical type for length-n strings over the Y-basis symbols {->, <-}.";
    let description = [{
        `!prelim_hlep.y<n>` is a purely classical type whose terms are
        length-`n` strings of the symbols `->` and `<-`. Analogous to
        `!prelim_hlep.x<n>`, but for the Y-basis. See `XType` above.

        TODO: decide representation/verification for `n` (e.g. non-negative).
    }];

    let parameters = (ins "int64_t":$size);
    let assemblyFormat = "`<` $size `>`";
}

#endif // INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPTYPES_TD_
