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
        Hybrid quantum-classical IR meant to serve as the
        entry point to the compilation pipeline.
    }];

    let name = "prelimhlep";
    let cppNamespace = "::qcc::prelimhlep";
    let useDefaultTypePrinterParser = 1;
    let useDefaultAttributePrinterParser = 1;
    let hasConstantMaterializer = 1;

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
