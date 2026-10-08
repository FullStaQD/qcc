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
// QubitLaneOpInterface
//===----------------------------------------------------------------------===//

def Qcc_QubitLaneOpInterface : OpInterface<"QubitLaneOpInterface"> {
  let description = [{
        A qubit lane is a qubit, or a vector of qubits, on its way through an operation: lane `i` is qubit operand `i`
        together with qubit result `i`, the same qubit before and after the operation (element by element for a
        vector). A `qcirc.single` has one lane, a `qcirc.pair` has two.

        A lane follows the identity of a qubit, not its state: `qcirc.pair swap` does not exchange its lanes.

        Every lane has both ends, so qubit sources (`qcc.static`) and sinks do not implement the interface. An
        implementing operation has no qubit operand or result outside its lanes: the qubit operands form one contiguous
        group, and the qubit results are the leading results.
    }];
  let cppNamespace = "::qcc";

  let methods = [
    InterfaceMethod<
      /*desc=*/"Returns the qubit operands of this operation, in lane order.",
      /*retTy=*/"::mlir::OperandRange",
      /*methodName=*/"getQubitOperands"
    >,
    InterfaceMethod<
      /*desc=*/"Returns the qubit results of this operation, in lane order.",
      /*retTy=*/"::mlir::ResultRange",
      /*methodName=*/"getQubitResults"
    >,
    InterfaceMethod<
      /*desc=*/"Returns the number of qubit lanes of this operation.",
      /*retTy=*/"unsigned",
      /*methodName=*/"getNumQubitLanes",
      /*args=*/(ins),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        return $_op.getQubitResults().size();
      }]
    >,
    InterfaceMethod<
      /*desc=*/"Returns the qubit operand of `lane`, which must be a lane of this operation.",
      /*retTy=*/"::mlir::Value",
      /*methodName=*/"getQubitOperand",
      /*args=*/(ins "unsigned":$lane),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        ::mlir::OperandRange operands = $_op.getQubitOperands();
        assert(lane < operands.size() && "no such qubit lane");
        return operands[lane];
      }]
    >,
    InterfaceMethod<
      /*desc=*/"Returns the qubit result of `lane`, which must be a lane of this operation.",
      /*retTy=*/"::mlir::Value",
      /*methodName=*/"getQubitResult",
      /*args=*/(ins "unsigned":$lane),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        ::mlir::ResultRange results = $_op.getQubitResults();
        assert(lane < results.size() && "no such qubit lane");
        return results[lane];
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
        // The qubit results are the leading results, so the result number is the lane.
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
def Qcc_SingleUseQubits : NativeOpTrait<"SingleUseQubits"> {
  let cppNamespace = "::qcc";
}

#endif // INCLUDE_QCC_DIALECT_QCC_IR_QCCINTERFACES_TD_
