#ifndef INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPTYPES_TD_
#define INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPTYPES_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"
include "PrelimHLEPDialect.td"


//===----------------------------------------------------------------------===//
// PrelimHLEP types
//
// See mlir/docs/Dialects/PrelimHLEP.md, section "Type System" and "Core
// Attributes and Ops" for the formal semantics these types stub out.
//===----------------------------------------------------------------------===//

class PrelimHLEPType<string name, string typeMnemonic>
    : TypeDef<PrelimHLEPDialect, name> {
    let mnemonic = typeMnemonic;
}

def LinType : PrelimHLEPType<"Lin", "lin"> {
    let summary = "The linearization of a hybrid type.";
    let description = [{
        `!prelim_hlep.lin<T>` is the purely-linear (quantum) type obtained by
        linearizing the hybrid type `T`, i.e. Lin[T] from the "Linearization"
        type constructor in the design doc. Values of this type behave as
        quantum values with a single use (see the `LinearHalo` function
        attribute).

        TODO: This functor is idempotent. See if this can be incorporated.
    }];

    let parameters = (ins "::mlir::Type":$elementType);
    let assemblyFormat = "`<` $elementType `>`";
}

def UnitType : PrelimHLEPType<"Unit", "unit"> {
    let summary = "The tensor unit of the linear product, opaque to generic optimizations.";
    let description = [{
        `!prelim_hlep.unit` represents the fiber bundle

            [ C ]
            [ | ]
            [ * ]

        i.e. a 1-dimensional Hilbert space over the singleton classical
        label. Its unique term is a complex phase. Unlike the builtin
        `none` type, values of this type must not be treated as carrying no
        information by generic (dialect-agnostic) optimizations, since that
        phase can become an observable relative phase once combined with
        other haloed or quantum values.

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
