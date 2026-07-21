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

        `PrelimHLEPDialect::verifyOperationAttribute` (see
        PrelimHLEPDialect.cpp) hooks into the verifier of *any* operation
        this attribute is attached to and currently only checks that the
        op is function-like (`FunctionOpInterface`) with a non-empty
        argument and result list, as a placeholder for the doc's "a
        halo'ed function does not have zero arguments" rule.

        TODO: full halo semantics (single-use of non-classical values via
        control flow analysis, treating classical types as implicitly
        haloed, etc.) is not implemented yet.
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

        A term with a coefficient of 1 may omit the `coefficient *` prefix, as
        in the `X[0] * Y[2]` term above. A term's factors may name each qubit
        (in `[0, qubitCount)`) at most once; qubits it does not name are
        implicitly the identity. Terms are stored internally as a flattened
        `termHeaders`/`factors` pair (grouping `factors` into per-term runs,
        one per `termHeaders` entry) rather than as nested arrays, to keep
        attribute storage allocation trivial; use `getTerms()` to recover the
        structured `Term` list.

        The verifier checks that `qubitCount` is positive, that every
        factor's qubit index is in range and unique within its term, that no
        term has a zero coefficient, and that no two terms are identical up
        to reordering of factors.

        TODO: consider canonicalization to merge terms that differ only by
        the order qubits were declared once operator-level canonicalization
        exists.
    }];

    let parameters = (ins
        "int64_t":$qubitCount,
        ArrayRefParameter<"::qcc::prelimhlep::HamiltonianTermHeader", "coefficient and factor count of each term">:$termHeaders,
        ArrayRefParameter<"::qcc::prelimhlep::PauliFactor", "Pauli factors of all terms, flattened and grouped by $termHeaders">:$factors
    );

    let extraClassDeclaration = [{
      /// A single summand `coefficient * factors[0] * factors[1] * ...` of a
      /// `HamiltonianAttr`.
      struct Term {
        double coefficient;
        ::llvm::ArrayRef<::qcc::prelimhlep::PauliFactor> factors;
      };

      /// Reconstructs the structured list of terms from the flattened
      /// `coefficients`/`termSizes`/`factors` parameters.
      ::llvm::SmallVector<Term> getTerms() const;
    }];

    let hasCustomAssemblyFormat = 1;
    let genVerifyDecl = 1;
}

#endif // INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPATTRS_TD_
