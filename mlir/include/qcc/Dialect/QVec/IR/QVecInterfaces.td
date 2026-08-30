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
        A qubit slot is one lane of qubits through an operation: a qubit vector operand together with the result that
        carries the same qubits back out. A `qvec.single` has one slot, `0`; a `qvec.pair` has two, `0` and `1`.

        The result in slot `i` is *tied* to the operand in slot `i`: both denote the same qubits, before and after the
        operation. Non-qubit results, such as measurement outcomes, do not correspond to (qubit) slots.
    }];
  let cppNamespace = "::qcc::qvec";

  let methods = [
    InterfaceMethod<
      /*desc=*/"Returns the number of qubit slots of this operation.",
      /*retTy=*/"unsigned",
      /*methodName=*/"getNumQubitSlots"
    >,
    InterfaceMethod<
      /*desc=*/"Returns the qubit vector operand in `slot`, which must be a slot of this operation.",
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
        Returns the qubit slot corresponding to `result`, or `nullopt` if there is none.

        Asserts that this operation is the owner of `result`.
      }],
      /*retTy=*/"::std::optional<unsigned>",
      /*methodName=*/"getQubitSlot",
      /*args=*/(ins "::mlir::OpResult":$result),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        assert(result.getOwner() == $_op.getOperation() && "result belongs to a different operation");
        for (unsigned slot = 0, numSlots = $_op.getNumQubitSlots(); slot < numSlots; ++slot) {
          if ($_op.getQubitResult(slot) == result) {
            return slot;
          }
        }
        return ::std::nullopt;
      }]
    >,
    InterfaceMethod<
      /*desc=*/[{
        Returns the operand `result` receives its qubits from, or a null `Value` if there is none.

        Asserts that this operation is the owner of `result`.

        A null return is a normal answer, not a failure: it says that `result` does not continue an existing qubit
        chain, either because it is not a qubit result at all or because this operation is where the qubits originate.
      }],
      /*retTy=*/"::mlir::Value",
      /*methodName=*/"getTiedQubitOperand",
      /*args=*/(ins "::mlir::OpResult":$result),
      /*methodBody=*/"",
      /*defaultImplementation=*/[{
        ::std::optional<unsigned> slot = $_op.getQubitSlot(result);
        return slot ? $_op.getQubitOperand(*slot) : ::mlir::Value();
      }]
    >
  ];

  let extraClassDeclaration = [{
        /// The qubit vector operands of this operation, slot by slot.
        ::llvm::SmallVector<::mlir::TypedValue<::mlir::VectorType>, 2> getQubitOperands() {
          ::llvm::SmallVector<::mlir::TypedValue<::mlir::VectorType>, 2> operands;
          for (unsigned slot = 0, numSlots = getNumQubitSlots(); slot < numSlots; ++slot) {
            operands.push_back(getQubitOperand(slot));
          }
          return operands;
        }
    }];
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECINTERFACES_TD_
