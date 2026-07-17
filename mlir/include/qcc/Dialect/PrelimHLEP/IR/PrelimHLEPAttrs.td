#ifndef INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPATTRS_TD_
#define INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPATTRS_TD_

include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/BuiltinAttributeInterfaces.td"
include "PrelimHLEPDialect.td"


//===----------------------------------------------------------------------===//
// PrelimHLEP attributes
//
// See mlir/docs/Dialects/PrelimHLEP.md, section "Core Attributes and Ops".
//===----------------------------------------------------------------------===//

class PrelimHLEPAttr<string name, string attrMnemonic, list<Trait> traits = []>
    : AttrDef<PrelimHLEPDialect, name, traits> {
    let mnemonic = attrMnemonic;
}

def HaloAttr : PrelimHLEPAttr<"Halo", "halo"> {
    let summary = "Marks a function as operating in a linear (haloed) context.";
    let description = [{
        Decorates a `func.func` (see "Functions in linear context" in the
        design doc) to indicate that, within the function body, classical
        types are implicitly treated as carrying a linear halo and every
        non-purely-classical value must have exactly one use.

        **IR Realization:**
        `func.func @my_func() -> ... attributes { prelim_hlep.halo }`

        TODO: the doc's example prints this as a bare marker in the
        attribute dictionary, which is the builtin pretty-printing shorthand
        for `UnitAttr`. Decide whether `HaloAttr` should stay a distinct
        (empty) attribute for future extension/verification, or whether
        usages should just be a builtin `UnitAttr` under the
        `prelim_hlep.halo` key.
        TODO: verifier enforcing halo semantics (no zero-argument/-result
        haloed functions, single-use of non-classical values via control
        flow analysis, etc.) is not implemented yet.
    }];
}

def HamiltonianAttr : PrelimHLEPAttr<"Hamiltonian", "hamiltonian"> {
    let summary = "A Lie algebra element of u(2^n) in the Pauli-product basis.";
    let description = [{
        Represents an element of u(2^n), given in the basis of n-fold Pauli
        products, for use as the generator argument of `prelim_hlep.exp`.

        **IR Realization:**
        ```mlir
        #operator = prelim_hlep.hamiltonian<3, X[0] * Y[2] + 1.5 * Z[1]>
        ```
        denoting sigma_X (x) id (x) sigma_Y + 1.5 * id (x) sigma_Z (x) id in u(2^3).

        TODO: `terms` is a placeholder representation (a flat array of
        opaque sub-attributes). Design a proper structured representation
        of a sum of scaled Pauli-product terms, together with a custom
        parser/printer matching the algebraic syntax shown above, and
        canonicalization/verification ensuring a normalized form (e.g. no
        duplicate/zero terms, qubit indices in range).
    }];

    let parameters = (ins "int64_t":$qubitCount, "::mlir::ArrayAttr":$terms);
    let assemblyFormat = "`<` $qubitCount `,` $terms `>`";
}

#endif // INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPATTRS_TD_
