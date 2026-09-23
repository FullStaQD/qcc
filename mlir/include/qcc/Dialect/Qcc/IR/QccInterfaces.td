// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QCC_IR_QCCINTERFACES_TD_
#define INCLUDE_QCC_DIALECT_QCC_IR_QCCINTERFACES_TD_

include "mlir/IR/Interfaces.td"

//===----------------------------------------------------------------------===//
// DeviceAttrInterface
//===----------------------------------------------------------------------===//

def QCC_DeviceAttrInterface : AttrInterface<"DeviceAttrInterface"> {
  let description = [{
        A device description: everything the compiler needs to know about the target machine that is not derivable
        from the program. The module attribute `qcc.device` accepts any attribute implementing this interface, so the
        driver and the entry-point handling never mention a concrete device kind.

        Concrete devices (e.g. `#magic.device`) expose their data through a C++ facade class rather than through
        this interface. Add methods here only once a second device kind needs them.
    }];
  let cppNamespace = "::qcc";

  let methods = [
    InterfaceMethod<
      /*desc=*/"Returns the human-readable device name.",
      /*retTy=*/"::llvm::StringRef",
      /*methodName=*/"getName"
    >
  ];
}

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCINTERFACES_TD_
