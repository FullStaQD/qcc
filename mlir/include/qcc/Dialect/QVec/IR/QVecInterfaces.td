// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef INCLUDE_QCC_DIALECT_QVEC_IR_QVECINTERFACES_TD_
#define INCLUDE_QCC_DIALECT_QVEC_IR_QVECINTERFACES_TD_

include "mlir/IR/OpBase.td"

//===----------------------------------------------------------------------===//
// QubitSlotOpInterface
//===----------------------------------------------------------------------===//

def QVec_QubitSlotOpInterface : OpInterface<"QubitSlotOpInterface"> {
  let description = [{
        A qubit slot is one lane of qubits through an operation: a qubit vector result together with the operand that
        carries the same qubits in (if the latter exists). A `qvec.single` has one slot, `0`; a `qvec.pair` has two, `0`
        and `1`.

        NOTE: Currently the design is asymmetric; a slot always corresponds to a result, but an operand might not exist.
        This accommodates qubit sources. In principle the reverse would be possible too (slot with an operand but no
        result) accommodating qubit sinks. We have decided against it so far. This is reflected in the signatures of the
        involved methods.
    }];
  let cppNamespace = "::qcc::qvec";

  let methods = [
    InterfaceMethod<
      /*desc=*/"Returns the number of qubit slots of this operation, one per qubit vector result.",
      /*retTy=*/"unsigned",
      /*methodName=*/"getNumQubitSlots"
    >,
    InterfaceMethod<
      /*desc=*/[{
        Returns the qubit vector operand in `slot`, which must be a slot of this operation, or a null value if the
        qubits in that slot originate in this operation.
      }],
      /*retTy=*/"::mlir::TypedValue<::mlir::VectorType>",
      /*methodName=*/"getQubitOperand",
      /*args=*/(ins "unsigned":$slot)
    >,
    InterfaceMethod<
      /*desc=*/"Returns the qubit vector result in `slot`, which must be a slot of this operation.",
      /*retTy=*/"::mlir::TypedValue<::mlir::VectorType>",
      /*methodName=*/"getQubitResult",
      /*args=*/(ins "unsigned":$slot)
    >,
    InterfaceMethod<
      /*desc=*/[{
        Returns the qubit slot `result` belongs to.

        Asserts that `result` is a qubit vector result of this operation. Every qubit vector result is a slot, so ask
        `isQubitVector` on the result type to find out whether this query applies.
      }],
      /*retTy=*/"unsigned",
      /*methodName=*/"getQubitSlot",
      /*args=*/(ins "::mlir::OpResult":$result),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        assert(result.getOwner() == $_op.getOperation() && "result belongs to a different operation");
        assert(::qcc::qvec::isQubitVector(result.getType()) && "not a qubit vector result");
        for (unsigned slot = 0, numSlots = $_op.getNumQubitSlots(); slot < numSlots; ++slot) {
          if ($_op.getQubitResult(slot) == result) {
            return slot;
          }
        }
        llvm_unreachable("qubit vector result outside the qubit slots");
      }]
    >,
    InterfaceMethod<
      /*desc=*/[{
        Returns the operand `result` receives its qubits from, or a null `Value` if the qubits originate in this
        operation.

        Asserts that `result` is a qubit vector result of this operation.

        A null return is a normal answer, not a failure: it says that `result` does not continue an existing qubit
        chain, because this operation is where its qubits originate.
      }],
      /*retTy=*/"::mlir::Value",
      /*methodName=*/"getTiedQubitOperand",
      /*args=*/(ins "::mlir::OpResult":$result),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        return $_op.getQubitOperand($_op.getQubitSlot(result));
      }]
    >
  ];

  let extraClassDeclaration = [{
        /// The qubit vector operands of this operation, slot by slot, skipping the slots whose qubits originate here.
        ::llvm::SmallVector<::mlir::TypedValue<::mlir::VectorType>, 2> getQubitOperands() {
          ::llvm::SmallVector<::mlir::TypedValue<::mlir::VectorType>, 2> operands;
          for (unsigned slot = 0, numSlots = getNumQubitSlots(); slot < numSlots; ++slot) {
            if (auto operand = getQubitOperand(slot)) {
              operands.push_back(operand);
            }
          }
          return operands;
        }
    }];
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECINTERFACES_TD_
