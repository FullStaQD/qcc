// RUN: qcc-translate --import-openqasm %S/Inputs/spec-examples/qft.qasm | qcc-translate --export-openqasm \
// RUN:   | diff %S/Inputs/spec-examples/qft.qasm -
// The export does not keep blank lines.
// RUN: qcc-translate --import-openqasm %S/Inputs/spec-examples/rb.qasm | qcc-translate --export-openqasm \
// RUN:   | diff -I '^$' %S/Inputs/spec-examples/rb.qasm -

// The examples of the OpenQASM specification that the importer supports so far survive an import and export.
