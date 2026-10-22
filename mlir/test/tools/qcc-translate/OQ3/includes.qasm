// RUN: split-file %s %t
// RUN: qcc-translate --import-openqasm -I %t/dir %t/main.qasm | FileCheck %s --check-prefix=CHECK-IR
// RUN: qcc-translate --import-openqasm -I %t/dir %t/main.qasm | qcc-translate --export-openqasm \
// RUN:   | FileCheck %s --check-prefix=CHECK-EXPORT --strict-whitespace
// RUN: qcc-translate --import-openqasm -I %t/dir %t/stdgates.qasm | FileCheck %s --check-prefix=CHECK-STDGATES

// An included file is parsed in place, in the scope of the program. Its statements are tagged with the include they
// came from, and the export prints the include line instead of them.

// These tests use `split-file` rather than `--split-input-file`: the name of a chunk is not that of a real file, so
// files next to it could not be found.

// `local.inc` is found next to the including file, `searched.inc` in the include directory. `nested.inc` is next to
// `searched.inc`, so it is found relative to the file that includes it.
// CHECK-IR:      oq3.include "local.inc" id 0{{$}}
// CHECK-IR-NEXT: oq3.qubit_decl "a" {oq3.from_include = 0 : i64}
// CHECK-IR-NEXT: oq3.include "searched.inc" id 1{{$}}
// CHECK-IR-NEXT: oq3.include "nested.inc" id 2 {oq3.from_include = 1 : i64}
// CHECK-IR-NEXT: oq3.qubit_decl "b" {oq3.from_include = 2 : i64}
// CHECK-IR-NEXT: oq3.constant #oq3.int<2> : !oq3.int {oq3.from_include = 1 : i64}
// CHECK-IR-NEXT: oq3.declare "c" {{.*}}{oq3.from_include = 1 : i64}
// Names from the included files are in scope afterwards.
// CHECK-IR:      oq3.gate_call @U
// CHECK-IR:      oq3.measure

// CHECK-EXPORT:      OPENQASM 3.1;
// CHECK-EXPORT-NEXT: include "local.inc";
// CHECK-EXPORT-NEXT: include "searched.inc";
// CHECK-EXPORT-NEXT: U(0, 0, 0) a;
// CHECK-EXPORT-NEXT: c[0] = measure b;

// A `stdgates.inc` on disk is not read yet, the built-in signature table describes it.
// CHECK-STDGATES:      oq3.include "stdgates.inc" id 0{{$}}
// CHECK-STDGATES-NEXT: oq3.qubit_decl "q"
// CHECK-STDGATES-NEXT: oq3.gate_call @h

//--- main.qasm
OPENQASM 3.1;
include "local.inc";
include "searched.inc";
U(0, 0, 0) a;
c[0] = measure b;
//--- local.inc
qubit a;
//--- dir/searched.inc
include "nested.inc";
bit[2] c;
//--- dir/nested.inc
qubit b;
//--- stdgates.qasm
include "stdgates.inc";
qubit q;
h q;
//--- dir/stdgates.inc
gate h a { U(pi/2, 0, pi) a; }
