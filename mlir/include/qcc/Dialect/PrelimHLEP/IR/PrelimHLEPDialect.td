#ifndef INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPDIALECT_TD_
#define INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPDIALECT_TD_

include "mlir/IR/DialectBase.td"
include "mlir/IR/AttrTypeBase.td"

//===----------------------------------------------------------------------===//
// PrelimHLEP dialect
//===----------------------------------------------------------------------===//

def PrelimHLEPDialect : Dialect {
    let summary = "PRELIMINARY High-level entry point dialect.";
    let description = [{
        Preliminary, draft implementation of the "high-level entry point"
        (HLEP) dialect: a hybrid quantum-classical IR meant to serve as the
        entry point to the compilation pipeline. See
        `mlir/docs/Dialects/PrelimHLEP.md` for the design rationale and the
        formal type-theoretic model this dialect stubs out.

        This is a work in progress. Types, attributes, and operations
        defined here are mostly stubs (declarations with at most minimal
        verification, no builders or lowering yet) tracking the draft
        design; see individual TODOs.

        See issue: https://github.com/FullStaQD/compiler/issues/34
    }];

    let name = "prelimhlep";
    let cppNamespace = "::qcc::prelimhlep";
    let useDefaultTypePrinterParser = 1;
    let useDefaultAttributePrinterParser = 1;

    let extraClassDeclaration = [{
        /// Verifies dialect attributes (e.g. `prelimhlep.halo`) attached to
        /// arbitrary operations, such as `func.func`. See
        /// PrelimHLEPDialect.cpp.
        ::mlir::LogicalResult
        verifyOperationAttribute(::mlir::Operation *op,
                                  ::mlir::NamedAttribute attribute) override;
    }];
}


#endif // INCLUDE_QCC_DIALECT_PRELIMHLEP_IR_PRELIMHLEPDIALECT_TD_
