// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// CHECK-LABEL: func.func @shared_type
func.func @shared_type(%a: i1, %b: i1) {
    test.observe %a, %b : i1, i1
    return
}

// A type shared by all operands is written once.
// CHECK:         test.observe %{{.*}}, %{{.*}} : i1{{$}}

// CHECK-LABEL: func.func @mixed_types
func.func @mixed_types(%a: i1, %b: i64) {
    test.observe %a, %b : i1, i64
    return
}

// CHECK:         test.observe %{{.*}}, %{{.*}} : i1, i64
