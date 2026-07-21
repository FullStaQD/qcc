#include "qcc/Dialect/PrelimHLEP/IR/PrelimHLEP.h"

#include <llvm/ADT/TypeSwitch.h>
#include <mlir/IR/DialectImplementation.h>
#include <mlir/Interfaces/ControlFlowInterfaces.h>
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

#include "LinearityChecker.cpp"

/// Checks that `op` is nested (directly or indirectly) within a
/// `prelim_hlep.halo`-attributed function: walks up ancestor operations, and
/// requires that the first one implementing `FunctionOpInterface` carries
/// the halo attribute.
static LogicalResult verifyWithinHaloedFunction(Operation* op) {
  std::string haloAttrName = (PrelimHLEPDialect::getDialectNamespace() + "." + HaloAttr::getMnemonic()).str();

  auto funcOp = op->getParentOfType<FunctionOpInterface>();
  if (!funcOp || !funcOp->hasAttr(haloAttrName)) {
    return op->emitOpError("expected to be nested within a '") << haloAttrName << "'-attributed function";
  }

  return success();
}

/// Checks that `op`'s single input/result pair (named accordingly in
/// diagnostics) have identical types.
static LogicalResult verifyInputResultTypesMatch(Operation* op, Type inputType, Type resultType) {
  if (inputType != resultType) {
    return op->emitOpError("expected result type (") << resultType << ") to match input type (" << inputType << ")";
  }
  return success();
}

LogicalResult ScaleOp::verify() {
  if (failed(verifyWithinHaloedFunction(getOperation()))) {
    return failure();
  }
  return verifyInputResultTypesMatch(getOperation(), getInput().getType(), getResult().getType());
}

LogicalResult AddPhaseOp::verify() {
  if (failed(verifyWithinHaloedFunction(getOperation()))) {
    return failure();
  }
  return verifyInputResultTypesMatch(getOperation(), getInput().getType(), getResult().getType());
}

/// Returns the "size" `n` of a basis element type -- the bit width of `iN`,
/// or the `n` of `!prelim_hlep.x<n>`/`!prelim_hlep.y<n>` -- or `nullopt` if
/// `type` is none of these.
static std::optional<int64_t> getBasisSize(Type type) {
  if (auto intType = dyn_cast<IntegerType>(type)) {
    return intType.getWidth();
  }
  if (auto xType = dyn_cast<XType>(type)) {
    return xType.getSize();
  }
  if (auto yType = dyn_cast<YType>(type)) {
    return yType.getSize();
  }
  return std::nullopt;
}

LogicalResult BaseChangeOp::verify() {
  if (failed(verifyWithinHaloedFunction(getOperation()))) {
    return failure();
  }

  auto inputType = dyn_cast<LinType>(getInput().getType());
  auto resultType = dyn_cast<LinType>(getResult().getType());
  if (!inputType || !resultType) {
    return emitOpError("expected input and result types to be '") << LinType::getMnemonic() << "' types";
  }

  std::optional<int64_t> inputSize = getBasisSize(inputType.getElementType());
  std::optional<int64_t> resultSize = getBasisSize(resultType.getElementType());
  if (!inputSize) {
    return emitOpError("expected input type's element type (")
           << inputType.getElementType() << ") to be an integer, 'x', or 'y' type";
  }
  if (!resultSize) {
    return emitOpError("expected result type's element type (")
           << resultType.getElementType() << ") to be an integer, 'x', or 'y' type";
  }
  if (*inputSize != *resultSize) {
    return emitOpError("expected input and result types to have the same qubit count, got ")
           << *inputSize << " and " << *resultSize;
  }

  return success();
}

LogicalResult OutputOp::verify() { return verifyWithinHaloedFunction(getOperation()); }

LogicalResult ConstantOp::verify() {
  auto resultType = dyn_cast<LinType>(getResult().getType());
  Type elementType = resultType ? resultType.getElementType() : nullptr;
  StringRef value = getValue();

  if (auto xType = dyn_cast_or_null<XType>(elementType)) {
    if (static_cast<int64_t>(value.size()) != xType.getSize()) {
      return emitOpError("expected a length-")
             << xType.getSize() << " string for result type " << resultType << ", got length " << value.size();
    }
    for (char c : value) {
      if (c != '+' && c != '-') {
        return emitOpError("expected only '+'/'-' symbols for result type ") << resultType << ", got '" << c << "'";
      }
    }
    return success();
  }

  if (auto yType = dyn_cast_or_null<YType>(elementType)) {
    if (static_cast<int64_t>(value.size()) != 2 * yType.getSize()) {
      return emitOpError("expected a length-")
             << (2 * yType.getSize()) << " string (" << yType.getSize() << " '->'/'<-' symbols) for result type "
             << resultType << ", got length " << value.size();
    }
    for (size_t i = 0, e = value.size(); i < e; i += 2) {
      StringRef symbol = value.substr(i, 2);
      if (symbol != "->" && symbol != "<-") {
        return emitOpError("expected only '->'/'<-' symbols for result type ")
               << resultType << ", got '" << symbol << "'";
      }
    }
    return success();
  }

  return emitOpError("expected result type to be '")
         << LinType::getMnemonic() << "<" << XType::getMnemonic() << "<n>>' or '" << LinType::getMnemonic() << "<"
         << YType::getMnemonic() << "<n>>', got " << getResult().getType();
}

LogicalResult ExpOp::verify() {
  if (failed(verifyWithinHaloedFunction(getOperation()))) {
    return failure();
  }

  if (failed(verifyInputResultTypesMatch(getOperation(), getInput().getType(), getResult().getType()))) {
    return failure();
  }

  auto inputType = dyn_cast<LinType>(getInput().getType());
  IntegerType elementType = inputType ? dyn_cast<IntegerType>(inputType.getElementType()) : nullptr;
  if (!elementType) {
    return emitOpError("expected input/result types to be purely-quantum '")
           << LinType::getMnemonic() << "<i<n>>' types, got " << getInput().getType();
  }

  int64_t qubitCount = getHamiltonian().getQubitCount();
  if (qubitCount != elementType.getWidth()) {
    return emitOpError("expected hamiltonian qubit count (")
           << qubitCount << ") to match input/result bit width (" << elementType.getWidth() << ")";
  }

  return success();
}

// Parses `( %arg : argType from %operand : operandType, ... ) -> ( resultType, ... ) region`.
ParseResult LinOp::parse(OpAsmParser& parser, OperationState& result) {
  SmallVector<OpAsmParser::Argument> blockArgs;
  SmallVector<OpAsmParser::UnresolvedOperand> operands;
  SmallVector<Type> operandTypes;

  auto parseBinding = [&]() -> ParseResult {
    OpAsmParser::Argument& blockArg = blockArgs.emplace_back();
    if (parser.parseArgument(blockArg, /*allowType=*/true) || parser.parseKeyword("from")) {
      return failure();
    }

    OpAsmParser::UnresolvedOperand& operand = operands.emplace_back();
    Type& operandType = operandTypes.emplace_back();
    return failure(parser.parseOperand(operand) || parser.parseColonType(operandType));
  };
  if (parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren, parseBinding)) {
    return failure();
  }

  SmallVector<Type> resultTypes;
  if (parser.parseArrow() || parser.parseCommaSeparatedList(OpAsmParser::Delimiter::Paren, [&]() {
        return parser.parseType(resultTypes.emplace_back());
      })) {
    return failure();
  }
  result.addTypes(resultTypes);

  Region* body = result.addRegion();
  if (parser.parseRegion(*body, blockArgs)) {
    return failure();
  }

  if (parser.resolveOperands(operands, operandTypes, parser.getCurrentLocation(), result.operands)) {
    return failure();
  }

  return parser.parseOptionalAttrDict(result.attributes);
}

void LinOp::print(OpAsmPrinter& p) {
  p << " (";
  llvm::interleaveComma(llvm::zip(getBody().front().getArguments(), getDelinearizedOperands()), p,
                        [&](const auto& binding) {
                          BlockArgument arg = std::get<0>(binding);
                          Value operand = std::get<1>(binding);
                          p << arg << " : " << arg.getType() << " from " << operand << " : " << operand.getType();
                        });
  p << ") -> (";
  llvm::interleaveComma(getResultTypes(), p);
  p << ") ";
  p.printRegion(getBody(), /*printEntryBlockArgs=*/false);
  p.printOptionalAttrDict((*this)->getAttrs());
}

LogicalResult LinOp::verify() {
  if (failed(verifyWithinHaloedFunction(getOperation()))) {
    return failure();
  }

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

  if (funcOp.getNumArguments() == 0) {
    return op->emitError("'") << haloAttrName
                              << "' function must not have zero arguments; use "
                                 "'!prelim_hlep.unit' instead";
  }
  if (funcOp.getNumResults() == 0) {
    return op->emitError("'") << haloAttrName
                              << "' function must not have zero results; use "
                                 "'!prelim_hlep.unit' instead";
  }

  if (!funcOp.isExternal()) {
    if (failed(checkSingleBlockRegions(op, haloAttrName))) {
      return failure();
    }

    LogicalResult result = success();
    op->walk([&](Operation* nestedOp) {
      for (Region& region : nestedOp->getRegions()) {
        for (Block& block : region) {
          for (BlockArgument arg : block.getArguments()) {
            if (isNotPurelyClassical(arg.getType()) &&
                failed(checkPreciselyOneUse(arg, "'" + haloAttrName + "' " + describeLinearValue(funcOp, arg)))) {
              result = failure();
            }
          }
        }
      }
      for (OpResult opResult : nestedOp->getResults()) {
        if (isNotPurelyClassical(opResult.getType()) &&
            failed(checkPreciselyOneUse(opResult, "'" + haloAttrName + "' " + describeLinearValue(funcOp, opResult)))) {
          result = failure();
        }
      }
    });
    if (failed(result)) {
      return failure();
    }
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
