#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <llvm/ADT/TypeSwitch.h>
#include <mlir/IR/DialectImplementation.h>
#include <mlir/Interfaces/FunctionInterfaces.h>

using namespace mlir;
using namespace qcc::prelimhlep;

#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPDialect.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPTypes.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPAttrs.cpp.inc"

#define GET_OP_CLASSES
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPOps.cpp.inc"

LogicalResult LinOp::verify() {
  Block& body = getBody().front();

  if (body.getNumArguments() != getDelinearizedOperands().size()) {
    return emitOpError("expected the body block to have as many arguments (")
           << body.getNumArguments() << ") as delinearized operands (" << getDelinearizedOperands().size() << ")";
  }

  for (unsigned i = 0, e = body.getNumArguments(); i < e; ++i) {
    Type elementType = dyn_cast<LinType>(getDelinearizedOperands()[i].getType()).getElementType();
    Type argType = body.getArgument(i).getType();
    if (argType != elementType) {
      return emitOpError("body block argument #")
             << i << " has type " << argType << ", expected the delinearized operand's element type " << elementType;
    }
  }

  auto output = dyn_cast<OutputOp>(body.getTerminator());
  if (!output) {
    return emitOpError("expected the body to be terminated with "
                       "'prelim_hlep.output'");
  }

  ValueRange delinearizedResults = output.getDelinearizedResults();
  ValueRange auxiliaryResults = output.getAuxiliaryResults();
  ResultRange results = getResults();
  if (results.size() != delinearizedResults.size() + auxiliaryResults.size()) {
    return emitOpError("expected ") << (delinearizedResults.size() + auxiliaryResults.size())
                                    << " results to match the number of 'prelim_hlep.output' "
                                       "operands, got "
                                    << results.size();
  }

  for (unsigned i = 0, e = delinearizedResults.size(); i < e; ++i) {
    auto resultType = dyn_cast<LinType>(results[i].getType());
    Type delinearizedType = delinearizedResults[i].getType();
    if (!resultType || resultType.getElementType() != delinearizedType) {
      return emitOpError("result #") << i << " has type " << results[i].getType()
                                     << ", expected the linearization of 'prelim_hlep.output' "
                                        "operand type "
                                     << delinearizedType;
    }
  }

  for (unsigned i = 0, e = auxiliaryResults.size(); i < e; ++i) {
    unsigned resultIdx = delinearizedResults.size() + i;
    Type auxType = auxiliaryResults[i].getType();
    if (results[resultIdx].getType() != auxType) {
      return emitOpError("result #") << resultIdx << " has type " << results[resultIdx].getType()
                                     << ", expected 'prelim_hlep.output' auxiliary operand type " << auxType;
    }
  }

  return success();
}

LogicalResult PrelimHLEPDialect::verifyOperationAttribute(Operation* op, NamedAttribute attribute) {
  std::string haloAttrName = (getNamespace() + "." + HaloAttr::getMnemonic()).str();
  if (attribute.getName() != haloAttrName) {
    return success();
  }

  auto funcOp = dyn_cast<FunctionOpInterface>(op);
  if (!funcOp) {
    return op->emitError("'") << haloAttrName << "' is only valid on function-like operations";
  }

  // TODO: this is a placeholder for the full LinearHalo verification
  // described in the design doc (single-use of non-classical values via
  // control-flow analysis, treating classical types as implicitly haloed,
  // etc.). For now we only check the doc's "a halo'ed function does not
  // have zero arguments" rule (and its dual for results): see "Halo Unit
  // Type" in mlir/docs/Dialects/PrelimHLEP.md.
  if (funcOp.getNumArguments() == 0) {
    return op->emitError("'") << haloAttrName
                              << "' function must not have zero arguments; use "
                                 "'!prelim_hlep.linear_unit' instead";
  }
  if (funcOp.getNumResults() == 0) {
    return op->emitError("'") << haloAttrName
                              << "' function must not have zero results; use "
                                 "'!prelim_hlep.linear_unit' instead";
  }

  return success();
}

void PrelimHLEPDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPTypes.cpp.inc"
      >();

  addAttributes<
#define GET_ATTRDEF_LIST
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPAttrs.cpp.inc"
      >();

  addOperations<
#define GET_OP_LIST
#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEPOps.cpp.inc"
      >();
}
