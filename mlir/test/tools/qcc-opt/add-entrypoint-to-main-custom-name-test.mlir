// RUN: qcc-opt %s --add-entrypoint-to-main="entry-point-name=kernel" | FileCheck %s

// With a custom entry-point name, @kernel gets the attribute.
func.func @kernel() {
    return
}

// CHECK-LABEL: func.func @kernel() attributes {qcc.entry_point}
