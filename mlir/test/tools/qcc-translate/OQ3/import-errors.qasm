// RUN: qcc-translate --import-openqasm --split-input-file --verify-diagnostics %s

// Errors and warnings of the OpenQASM importer: invalid programs, deprecated syntax, and valid programs that use
// constructs not supported yet.

// expected-error-re @below {{OpenQASM 2.0 is not supported; supported versions are {{.*}}}}
OPENQASM 2.0;

// -----

// The development version needs `--oq3-allow-dev-version`.
// expected-error @below {{OpenQASM 3.2 is not released yet}}
// expected-note-re @below {{qcc implements the development specification as of {{.*}}; use --oq3-allow-dev-version to import the program anyway}}
OPENQASM 3.2;

// -----

// expected-warning @below {{the program has no version line; assuming 'OPENQASM 3.1;'}}
qubit q;
// expected-error @below {{the version line must be the first statement of the program}}
OPENQASM 3.1;

// -----

OPENQASM 3.1;

qubit q;
// expected-error @below {{unknown name 'h'}}
// expected-note @below {{'h' is a standard gate; it needs an earlier 'include "stdgates.inc";'}}
h q;

// -----

OPENQASM 3.1;

include "stdgates.inc";
qubit q;
// expected-error @below {{gate 'rx' takes 1 parameter(s), got 0}}
rx q;

// -----

OPENQASM 3.1;

include "stdgates.inc";
qubit q;
// expected-error @below {{gate 'cx' takes 2 qubit(s), got 1}}
cx q;

// -----

OPENQASM 3.1;

// The built-in gates need no include.
qubit q;
// expected-error @below {{gate 'U' takes 3 parameter(s), got 1}}
U(0) q;

// -----

OPENQASM 3.1;

include "stdgates.inc";
qubit[2] a;
qubit[3] b;
// expected-error @below {{a register of size 3 cannot be broadcast together with one of size 2}}
// expected-note @below {{the other register is here}}
cx a, b;

// -----

OPENQASM 3.1;

// expected-note @below {{the previous declaration is here}}
qubit q;
// expected-error @below {{'q' is already declared}}
bit q;

// -----

OPENQASM 3.1;

// expected-error @below {{'pi' is a built-in name and cannot be declared}}
qubit pi;

// -----

OPENQASM 3.1;

include "stdgates.inc";
// expected-error @below {{'x' is already defined as a gate by 'stdgates.inc'}}
qubit x;

// -----

OPENQASM 3.1;

// expected-note @below {{the declaration is here}}
qubit x;
// expected-error @below {{'stdgates.inc' defines the gate 'x', which is already declared}}
include "stdgates.inc";

// -----

OPENQASM 3.1;

// expected-note @below {{the first include is here}}
include "stdgates.inc";
// expected-error-re @below {{'stdgates.inc' was already included at line {{[0-9]+}}; its definitions would be redeclared}}
include "stdgates.inc";

// -----

OPENQASM 3.1;

// expected-error @below {{cannot find the include file 'missing.inc'}}
include "missing.inc";

// -----

OPENQASM 3.1;

// expected-warning @below {{'qreg' is deprecated; declare 'q' with 'qubit[n] q;' instead}}
qreg q[2];
// expected-warning @below {{'creg' is deprecated; declare 'c' with 'bit c;' instead}}
creg c;

// -----

OPENQASM 3.1;

include "stdgates.inc";
qubit[2] q;
// expected-error @below {{index 2 is out of range for 'q' of size 2}}
x q[2];

// -----

OPENQASM 3.1;

include "stdgates.inc";
qubit[2] q;
// Negative indices count from the end.
x q[-2];
// expected-error @below {{index -3 is out of range for 'q' of size 2}}
x q[-3];

// -----

OPENQASM 3.1;

include "stdgates.inc";
qubit q;
// expected-error @below {{'q' is a single qubit and cannot be indexed}}
x q[0];

// -----

OPENQASM 3.1;

bit c;
// expected-error @below {{a size must be an integer, got 'bit'}}
qubit[c] q;

// -----

OPENQASM 3.1;

// expected-error @below {{a size must be an integer, got 'float'}}
qubit[2.0] q;

// -----

OPENQASM 3.1;

// expected-error @below {{a size must be non-negative, got -1}}
qubit[-1] q;

// -----

OPENQASM 3.1;

// expected-error @below {{division by zero in a constant expression}}
// expected-error @below {{a size must be a constant expression}}
qubit[1 / 0] q;

// -----

OPENQASM 3.1;

qubit[2] q;
// expected-error @below {{cannot initialize the variable with a value of type 'bit[2]' a 'bit'}}
bit c = measure q;

// -----

OPENQASM 3.1;

// expected-error @below {{cannot initialize the variable with a value of type 'bit[3]' a 'bit[2]'}}
bit[2] c = "011";

// -----

OPENQASM 3.1;

// expected-error @below {{only the integers 0 and 1 convert to a 'bit' implicitly}}
bit c = 2;

// -----

OPENQASM 3.1;

qubit q;
// expected-error @below {{expected a statement, but 'q' is a qubit}}
q = measure q;

// -----

OPENQASM 3.1;

bit c;
// expected-error @below {{'c' is not a qubit}}
reset c;

// -----

OPENQASM 3.1;

bit c;
// expected-error @below {{'c' is a single bit and cannot be indexed}}
c[0] = 1;

// -----

OPENQASM 3.1;

qubit q;
// expected-error @below {{unknown variable 'd'}}
measure q -> d;

// -----

OPENQASM 3.1;

// expected-error @below {{unknown name 'n'}}
qubit[n] q;

// -----

OPENQASM 3.1;

qubit q;
// expected-error @below {{the qubit 'q' cannot be used in an expression}}
bit c = q;

// -----

OPENQASM 3.1;

// expected-error @below {{a physical qubit cannot be used in an expression}}
bit c = $0;

// -----

OPENQASM 3.1;

@ns.annotation
// expected-error @below {{annotations must be followed by a statement}}
pragma ns.name

// -----

OPENQASM 3.1;

// expected-error @below {{expected the content of the pragma on the same line}}
pragma

// -----

OPENQASM 3.1;

// expected-error @below {{expected ';', got 'q'}}
qubit p q;

// -----

OPENQASM 3.1;

// expected-error @below {{invalid integer literal}}
qubit[0b12] q;

// -----

OPENQASM 3.1;

// expected-error @below {{invalid number}}
qubit[2x] q;

// -----

OPENQASM 3.1;

// expected-error @below {{unexpected character}}
qubit ? q;

// -----

OPENQASM 3.1;

// expected-error @below {{a string in an expression must be a bitstring such as "0101"}}
bit[2] c = "0a";

// -----

OPENQASM 3.1;

// Constructs of later stages.

// expected-error @below {{gate definitions are not supported yet}}
gate g q { }

// -----

OPENQASM 3.1;

// expected-error @below {{declarations of type 'int' are not supported yet}}
int[32] i;

// -----

OPENQASM 3.1;

bit c;
// expected-error @below {{control flow ('if') is not supported yet}}
if (c) { }

// -----

OPENQASM 3.1;

include "stdgates.inc";
qubit[2] q;
// expected-error @below {{gate modifiers are not supported yet}}
ctrl @ x q[0], q[1];

// -----

OPENQASM 3.1;

include "stdgates.inc";
qubit[3] q;
// expected-error @below {{slices and multiple indices are not supported yet}}
x q[0:1];

// -----

OPENQASM 3.1;

include "stdgates.inc";
qubit q;
// expected-error @below {{the operator '**' is not supported yet}}
rx(2 ** 3) q;

// -----

OPENQASM 3.1;

bit[2] c;
// expected-error @below {{compound assignments are not supported yet}}
c |= "01";

// -----

OPENQASM 3.1;

include "stdgates.inc";
qubit q;
// expected-error @below {{built-in functions are not supported yet}}
rx(sin(1)) q;

// -----

OPENQASM 3.1;

include "stdgates.inc";
qubit q;
// expected-error @below {{durations of gate calls are not supported yet}}
x[100ns] q;

// -----

OPENQASM 3.1;

// expected-error @below {{unterminated block comment}}
qubit q; /* no end
