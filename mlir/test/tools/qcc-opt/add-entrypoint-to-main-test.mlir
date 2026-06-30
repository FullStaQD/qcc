// RUN: qcc-opt %s --add-entrypoint-to-main --split-input-file | FileCheck %s

// Adds the attribute to a plain @main.
func.func @main() -> i64 {
    %0 = arith.constant 0 : i64
    return %0 : i64
}

// CHECK-LABEL: func.func @main() -> i64 attributes {qcc.entry_point}
// CHECK:   %[[C0:.*]] = arith.constant 0 : i64
// CHECK:   return %[[C0]] : i64

// -----

// Idempotent: an already-annotated @main is left as is.
func.func @main() -> i64 attributes { qcc.entry_point } {
    %0 = arith.constant 0 : i64
    return %0 : i64
}

// CHECK-LABEL: func.func @main() -> i64 attributes {qcc.entry_point}

// -----

// An entry-point already annotated on another function does NOT prevent
// @main from being marked: both end up with the attribute.
module {
  func.func @main() {
    return
  }
  func.func @other() attributes { qcc.entry_point } {
    return
  }
}

// CHECK-LABEL: func.func @main() attributes {qcc.entry_point}
// CHECK:       func.func @other() attributes {qcc.entry_point}
