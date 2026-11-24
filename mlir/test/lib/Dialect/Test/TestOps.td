// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef TEST_LIB_DIALECT_TEST_TESTOPS_TD_
#define TEST_LIB_DIALECT_TEST_TESTOPS_TD_

include "TestDialect.td"

include "mlir/IR/OpBase.td"

//===----------------------------------------------------------------------===//
// Test operations
//===----------------------------------------------------------------------===//

class Test_Op<string mnemonic, list<Trait> traits = []> : Op<Test_Dialect, mnemonic, traits>;

def Test_SinkOp : Test_Op<"sink"> {
  let summary = "a use of its operands that is never dead";
  let description = [{
        Gives its operands a use that passes never erase as dead code, so the operations computing them are never dead
        either. It does not declare its memory effects, so passes must assume arbitrary side effects.

        It is no optimization barrier: passes may still replace its operands by equivalent values, e.g. by folding or
        merging the operations that compute them.

        The operand types are written once if all operands share one type.

        Example:
        ```mlir
        test.sink %a, %b : vector<1x!qcc.qubit>
        test.sink %c, %d : vector<1x!qcc.qubit>, vector<3x!qcc.qubit>
        ```
    }];

  let arguments = (ins Variadic<AnyType>:$values);

  let assemblyFormat = [{
        attr-dict ($values^ `:` custom<SharedTypes>(ref($values), type($values)))?
    }];
}

#endif // TEST_LIB_DIALECT_TEST_TESTOPS_TD_
