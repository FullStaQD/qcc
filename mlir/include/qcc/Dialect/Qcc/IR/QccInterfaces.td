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
include "mlir/IR/OpBase.td"

//===----------------------------------------------------------------------===//
// DeviceAttrInterface
//===----------------------------------------------------------------------===//

def QCC_DeviceAttrInterface : AttrInterface<"DeviceAttrInterface"> {
  let description = [{
        A device description: everything the compiler needs to know about the target machine that is not derivable
        from the program. The module attribute `qcc.device` accepts any attribute implementing this interface, so the
        driver and the entry-point handling never mention a concrete device kind.

        Concrete devices (e.g. `#magic.device`) expose their data through a C++ class (e.g. `MagicDevice`) rather than
        through this interface. Add methods here only once a second device kind needs them.
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

//===----------------------------------------------------------------------===//
// ClassicalTypeInterface
//===----------------------------------------------------------------------===//

def Qcc_ClassicalTypeInterface : TypeInterface<"ClassicalTypeInterface"> {
  let description = [{
        A marker for dialect types of classical values, such as `!qcc.angle`. Only classical values can be stored in a
        `!qcc.ref`.

        The builtin integer, floating-point, `index`, and `complex` types are classical as well, and so are tensors
        and vectors of classical elements (see `qcc::isClassicalType`).
    }];
  let cppNamespace = "::qcc";
}

//===----------------------------------------------------------------------===//
// QubitLaneOpInterface
//===----------------------------------------------------------------------===//

def Qcc_QubitLaneOpInterface : OpInterface<"QubitLaneOpInterface"> {
  let description = [{
        An operation with this interface takes its qubits as its leading operands and returns exactly these qubits as
        its leading results, in the same order: result `i` is operand `i` after the operation. Such an operand/result
        pair is a *lane*, and it may also be a vector of qubits. A `qcirc.single` has one lane, a `qcirc.pair` has two.
        Qubit sources (`qcc.static`) and sinks therefore do not implement the interface.

        A lane follows the identity of a qubit, not its state: `qcirc.pair swap` does not exchange its lanes.
    }];
  let cppNamespace = "::qcc";

  let methods = [
    InterfaceMethod<
      /*desc=*/"Returns the number of qubit lanes of this operation.",
      /*retTy=*/"unsigned",
      /*methodName=*/"getNumQubitLanes",
      /*args=*/(ins),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        return ::qcc::detail::getNumLeadingQubits($_op->getResultTypes());
      }]
    >,
    InterfaceMethod<
      /*desc=*/"Returns the qubit operands of this operation, in lane order.",
      /*retTy=*/"::mlir::OperandRange",
      /*methodName=*/"getQubitOperands",
      /*args=*/(ins),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        return $_op->getOperands().take_front($_op.getNumQubitLanes());
      }]
    >,
    InterfaceMethod<
      /*desc=*/"Returns the qubit results of this operation, in lane order.",
      /*retTy=*/"::mlir::ResultRange",
      /*methodName=*/"getQubitResults",
      /*args=*/(ins),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        return $_op->getResults().take_front($_op.getNumQubitLanes());
      }]
    >,
    InterfaceMethod<
      /*desc=*/"Returns the qubit operand of `lane`, which must be a lane of this operation.",
      /*retTy=*/"::mlir::Value",
      /*methodName=*/"getQubitOperand",
      /*args=*/(ins "unsigned":$lane),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        assert(lane < $_op.getNumQubitLanes() && "no such qubit lane");
        return $_op->getOperand(lane);
      }]
    >,
    InterfaceMethod<
      /*desc=*/"Returns the qubit result of `lane`, which must be a lane of this operation.",
      /*retTy=*/"::mlir::Value",
      /*methodName=*/"getQubitResult",
      /*args=*/(ins "unsigned":$lane),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        assert(lane < $_op.getNumQubitLanes() && "no such qubit lane");
        return $_op->getResult(lane);
      }]
    >,
    InterfaceMethod<
      /*desc=*/[{
        Returns the operand in the lane of `result`, which must be a qubit result of this operation: the same qubit
        before the operation.
      }],
      /*retTy=*/"::mlir::Value",
      /*methodName=*/"getTiedQubitOperand",
      /*args=*/(ins "::mlir::OpResult":$result),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        assert(result.getOwner() == $_op.getOperation() && "result belongs to a different operation");
        // The result number is the lane.
        return $_op.getQubitOperand(result.getResultNumber());
      }]
    >
  ];

  let verify = [{ return ::qcc::detail::verifyQubitLaneOpInterface($_op); }];
}

//===----------------------------------------------------------------------===//
// Traits
//===----------------------------------------------------------------------===//

// Enforces the affine constraint on `!qcc.qubit` by usage counting. Only use where this is appropriate.
def Qcc_NoMultiUseQubits : NativeOpTrait<"NoMultiUseQubits"> {
  let cppNamespace = "::qcc";
}

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCINTERFACES_TD_
