#pragma once

#include <mlir/IR/BuiltinOps.h>
#include <mlir/IR/DialectImplementation.h>
#include <mlir/IR/PatternMatch.h>
#include <mlir/IR/Visitors.h>

//===----------------------------------------------------------------------===//
// PrelimHLEP Dialect
//===----------------------------------------------------------------------===//

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPDialect.h.inc"

//===----------------------------------------------------------------------===//
// PrelimHLEP Types
//===----------------------------------------------------------------------===//

#define GET_TYPEDEF_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPTypes.h.inc"

//===----------------------------------------------------------------------===//
// PrelimHLEP Attributes
//===----------------------------------------------------------------------===//

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPAttrs.h.inc"

//===----------------------------------------------------------------------===//
// PrelimHLEP Operations
//===----------------------------------------------------------------------===//

#define GET_OP_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPOps.h.inc"
