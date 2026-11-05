// RUN: qcc-translate --import-openqasm --oq3-allow-dev-version --split-input-file --verify-diagnostics %s

// Errors of the OpenQASM importer that only the development version 3.2 reports.

OPENQASM 3.2;

include "stdgates.inc";
qubit q;
// 3.2 drops the built-in function `pow`, so `pow` is only the gate modifier.
// expected-error @below {{'pow' is a gate modifier, not a function; use the '**' operator}}
rx(pow(2, 2)) q;
