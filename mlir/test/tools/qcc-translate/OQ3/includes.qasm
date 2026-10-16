// RUN: split-file %s %t
// RUN: qcc-translate --import-openqasm -I %t/dir %t/main.qasm | FileCheck %s
// RUN: qcc-translate --import-openqasm -I %t/dir %t/main.qasm | qcc-translate --export-openqasm | diff %t/main.qasm -
// RUN: not qcc-translate --import-openqasm %t/main.qasm 2>&1 | FileCheck %s --check-prefix=NOT-FOUND
// RUN: not qcc-translate --import-openqasm %t/cycle.qasm 2>&1 | FileCheck %s --check-prefix=CYCLE
// RUN: not qcc-translate --import-openqasm %t/versioned.qasm 2>&1 | FileCheck %s --check-prefix=VERSIONED
// RUN: not qcc-translate --import-openqasm %t/redeclared.qasm 2>&1 | FileCheck %s --check-prefix=REDECLARED
// RUN: qcc-translate --import-openqasm --oq3-allow-unresolved-includes %t/unresolved.qasm \
// RUN:   | FileCheck %s --check-prefix=UNRESOLVED
// RUN: qcc-translate --import-openqasm --oq3-allow-unresolved-includes %t/unresolved.qasm \
// RUN:   | qcc-translate --export-openqasm | diff %t/unresolved.qasm -

// An included file is parsed in place, in the scope of the program. Its statements are tagged with the include they
// came from, and the export prints the include line instead of them.

// `local.inc` is found next to the including file, `searched.inc` in the include directory. `nested.inc` is next to
// `searched.inc`, so it is found relative to the file that includes it.
// CHECK:      oq3.include "local.inc" id 0 hash "{{[0-9a-f]+}}"
// CHECK-NEXT: oq3.comment "// in local.inc" {oq3.from_include = 0 : i64}
// CHECK-NEXT: oq3.qubit_decl "a" {oq3.from_include = 0 : i64}
// CHECK-NEXT: oq3.include "searched.inc" id 1 hash
// CHECK-NEXT: oq3.include "nested.inc" id 2 hash "{{.*}}" {oq3.from_include = 1 : i64}
// CHECK-NEXT: oq3.qubit_decl "b" {oq3.from_include = 2 : i64}
// CHECK-NEXT: oq3.constant #oq3.int<2> : !oq3.int {oq3.from_include = 1 : i64}
// CHECK-NEXT: oq3.declare "c" {{.*}}{oq3.from_include = 1 : i64}
// Names from the included files are in scope afterwards.
// CHECK:      oq3.gate_call @U
// CHECK:      oq3.measure

// NOT-FOUND: error: cannot find the include file 'searched.inc'

// CYCLE:      cycle-b.inc:1:1: error: including 'cycle-a.inc' here forms an include cycle
// CYCLE-NEXT: include "cycle-a.inc";

// VERSIONED: versioned.inc:1:1: error: an included file cannot have a version line

// Including the same file twice declares its names twice.
// REDECLARED: local.inc:2:7: error: 'a' is already declared

// UNRESOLVED:      oq3.include "vendor.inc" id 0 unresolved
// UNRESOLVED-NEXT: %[[N:.*]] = oq3.unresolved "n" : !oq3.unknown
// UNRESOLVED-NEXT: %[[Q:.*]] = oq3.qubit_decl "q" [%[[N]] : !oq3.unknown] : !oq3.qreg<?>
// UNRESOLVED-NEXT: %[[THETA:.*]] = oq3.unresolved "theta" : !oq3.unknown
// UNRESOLVED-NEXT: oq3.gate_call @vendor_gate(%[[THETA]] : !oq3.unknown) [%[[Q]] : !oq3.qreg<?>]
// UNRESOLVED-NEXT: %[[ONE:.*]] = oq3.constant #oq3.int<1> : !oq3.int
// UNRESOLVED-NEXT: oq3.unresolved_call "vendor_setup"(%[[ONE]]) : (!oq3.int) -> !oq3.unknown
// UNRESOLVED-NEXT: oq3.gate_call @vendor_marker{{$}}

//--- main.qasm
OPENQASM 3.1;
include "local.inc";
include "searched.inc";
U(0, 0, 0) a;
c[0] = measure b;
//--- local.inc
// in local.inc
qubit a;
//--- dir/searched.inc
include "nested.inc";
bit[2] c;
//--- dir/nested.inc
qubit b;
//--- cycle.qasm
include "cycle-a.inc";
//--- cycle-a.inc
include "cycle-b.inc";
//--- cycle-b.inc
include "cycle-a.inc";
//--- versioned.qasm
include "versioned.inc";
//--- versioned.inc
OPENQASM 3.1;
//--- redeclared.qasm
include "local.inc";
include "local.inc";
//--- unresolved.qasm
include "vendor.inc";
qubit[n] q;
vendor_gate(theta) q;
vendor_setup(1);
vendor_marker;
