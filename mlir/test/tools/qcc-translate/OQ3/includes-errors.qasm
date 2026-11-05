// RUN: split-file %s %t
// RUN: not qcc-translate --import-openqasm %t/main.qasm 2>&1 | FileCheck %s --check-prefix=CHECK-NOT-FOUND
// RUN: not qcc-translate --import-openqasm %t/cycle.qasm 2>&1 | FileCheck %s --check-prefix=CHECK-CYCLE
// RUN: not qcc-translate --import-openqasm %t/versioned.qasm 2>&1 | FileCheck %s --check-prefix=CHECK-VERSIONED
// RUN: not qcc-translate --import-openqasm %t/redeclared.qasm 2>&1 | FileCheck %s --check-prefix=CHECK-REDECLARED

// Errors in resolving and parsing included files. The errors in an included file are reported there, so the tests use
// `split-file` and FileCheck rather than `--verify-diagnostics`.

// Without `-I`, `searched.inc` is not found.
// CHECK-NOT-FOUND: error: cannot find the include file 'searched.inc'

// CHECK-CYCLE:      cycle-b.inc:1:1: error: including 'cycle-a.inc' here forms an include cycle
// CHECK-CYCLE-NEXT: include "cycle-a.inc";

// CHECK-VERSIONED: versioned.inc:1:1: error: an included file cannot have a version line

// Including the same file twice declares its names twice.
// CHECK-REDECLARED: local.inc:1:7: error: 'a' is already declared

//--- main.qasm
include "searched.inc";
//--- dir/searched.inc
bit c;
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
//--- local.inc
qubit a;
