// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_HLEP_IR_HLEPINTERFACES_TD_
#define INCLUDE_QCC_DIALECT_HLEP_IR_HLEPINTERFACES_TD_

include "mlir/IR/OpBase.td"

//===----------------------------------------------------------------------===//
// LinearityAwareOpInterface
//===----------------------------------------------------------------------===//

def HLEP_LinearityAwareOpInterface : OpInterface<"LinearityAwareOpInterface"> {
  let description = [{
    Marks an operation as allowed to handle values subject to linearity (e.g.
    `!hlep.lin<...>`) inside a `hlep.halo` function, as an operand, result,
    or region argument, or by containing a use of such a value in one of its
    regions.
  }];
  let cppNamespace = "::qcc::hlep";

  let methods = [
    InterfaceMethod<
      /*desc=*/[{
        Verifies that this op handles its values subject to linearity correctly.
      }],
      /*retTy=*/"::llvm::LogicalResult",
      /*methodName=*/"verifyLinearValueHandling",
      /*args=*/(ins),
      /*methodBody=*/[{}],
      /*defaultImplementation=*/[{ return ::mlir::success(); }]
    >,
  ];
}

#endif // INCLUDE_QCC_DIALECT_HLEP_IR_HLEPINTERFACES_TD_
