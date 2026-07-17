// UNSUPPORTED: hisep-q

// RUN: qcc --list-targets | FileCheck %s --check-prefix=CHECK-LIST
// RUN: not qcc --target=hisep-q %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR

// CHECK-LIST: Available targets for --target:
// CHECK-LIST-NOT: hisep-q
// CHECK-ERR: error: unknown target 'hisep-q'

func.func @main() attributes { qcc.entry_point } {
    return
}
