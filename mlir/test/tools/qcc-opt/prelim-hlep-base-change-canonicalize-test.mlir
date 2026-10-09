// RUN: qcc-opt %s --split-input-file --canonicalize | FileCheck %s
// RUN: qcc-opt %s --split-input-file --prelim-hlep-merge-lin | FileCheck %s

// Base changes to the same type are dropped.

func.func @identity(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %r = prelimhlep.base_change %q : !prelimhlep.lin<i1> -> !prelimhlep.lin<i1>
    return %r : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @identity(
// CHECK-SAME:      [[Q:%.+]]: !prelimhlep.lin<i1>
// CHECK-NOT:     prelimhlep.base_change
// CHECK:         return [[Q]]

// -----

// A base change and its inverse cancel.

func.func @round_trip(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<i1> attributes { prelimhlep.halo } {
    %x = prelimhlep.base_change %q : !prelimhlep.lin<i1> -> !prelimhlep.lin<!prelimhlep.x<1>>
    %z = prelimhlep.base_change %x : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<i1>
    return %z : !prelimhlep.lin<i1>
}

// CHECK-LABEL: func.func @round_trip(
// CHECK-SAME:      [[Q:%.+]]: !prelimhlep.lin<i1>
// CHECK-NOT:     prelimhlep.base_change
// CHECK:         return [[Q]]

// -----

// A chain of base changes between different bases becomes a single one.

func.func @chain(%q : !prelimhlep.lin<i1>) -> !prelimhlep.lin<!prelimhlep.y<1>> attributes { prelimhlep.halo } {
    %x = prelimhlep.base_change %q : !prelimhlep.lin<i1> -> !prelimhlep.lin<!prelimhlep.x<1>>
    %y = prelimhlep.base_change %x : !prelimhlep.lin<!prelimhlep.x<1>> -> !prelimhlep.lin<!prelimhlep.y<1>>
    return %y : !prelimhlep.lin<!prelimhlep.y<1>>
}

// CHECK-LABEL: func.func @chain(
// CHECK-SAME:      [[Q:%.+]]: !prelimhlep.lin<i1>
// CHECK:         [[Y:%.+]] = prelimhlep.base_change [[Q]] : !prelimhlep.lin<i1> -> !prelimhlep.lin<!prelimhlep.y<1>>
// CHECK-NOT:     prelimhlep.base_change
// CHECK:         return [[Y]]
