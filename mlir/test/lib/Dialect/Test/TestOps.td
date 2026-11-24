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

def Test_ObserveOp : Test_Op<"observe"> {
  let summary = "observes its operands";
  let description = [{
        Stands in for whatever a program does to make values observable, e.g. recording measurement results, without
        adding operations the pass under test would transform as well. It declares no memory effects, so passes must
        assume arbitrary side effects: they never erase it, and the values it observes stay alive.

        The operand types are written once if all operands share one type.

        Example:
        ```mlir
        test.observe %a, %b : vector<1x!qcc.qubit>
        test.observe %c, %d : vector<1x!qcc.qubit>, vector<3x!qcc.qubit>
        ```
    }];

  let arguments = (ins Variadic<AnyType>:$values);

  let assemblyFormat = [{
        attr-dict ($values^ `:` custom<SharedTypes>(ref($values), type($values)))?
    }];
}

#endif // TEST_LIB_DIALECT_TEST_TESTOPS_TD_
