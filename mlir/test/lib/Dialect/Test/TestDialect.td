// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#ifndef TEST_LIB_DIALECT_TEST_TESTDIALECT_TD_
#define TEST_LIB_DIALECT_TEST_TESTDIALECT_TD_

include "mlir/IR/DialectBase.td"

//===----------------------------------------------------------------------===//
// Test dialect
//===----------------------------------------------------------------------===//

def Test_Dialect : Dialect {
  let name = "test";
  let summary = "Test-only operations for the lit tests.";
  let description = [{
        Holds operations that lit tests need but programs never contain. Like upstream MLIR's `test` dialect, it is
        registered only in the development tools (e.g. `qcc-opt`, `qcc-lsp-server`), never in `qcc`.
    }];
  let cppNamespace = "::qcc::test";
}

#endif // TEST_LIB_DIALECT_TEST_TESTDIALECT_TD_
