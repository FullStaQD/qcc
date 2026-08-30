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
        FIXME: improve docs

        An operation with *qubit slots* consumes and produces its qubits in numbered lanes. Slot `n` names one qubit
        vector operand together with the result that carries the same qubits back out, so a `qvec.pair` has two slots
        (first and second qubit vector) while a `qvec.single` has one.

        Slots are how a pass talks about the qubits of an operation without knowing which operation it is: they give a
        uniform name to what the operation calls `qubits_in` or `lhs_in`, and they make the qubit dataflow explicit.
        Tracing slot `n`'s result back to slot `n`'s operand is what lets a pass recover where a qubit vector came
        from; batching several operations into one is a matter of concatenating their vectors slot by slot.

        Results outside the slots exist -- the classical bits of a measurement are one -- and are simply not part of
        the qubit dataflow.
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
        Returns the slot `result` is the qubit result of, or `nullopt` if it is not one.

        `result` must belong to this operation. A result outside the slots -- the bits of a measurement, say -- is a
        normal answer, not a failure.
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
}

#endif // INCLUDE_QCC_DIALECT_QVEC_IR_QVECINTERFACES_TD_
