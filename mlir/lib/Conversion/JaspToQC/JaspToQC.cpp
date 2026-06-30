// ===----------------------------------------------------------------------===//
//
// Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
// Exceptions.
// See <repo-root>/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// ===----------------------------------------------------------------------===//

#include "qcc/Conversion/JaspToQC/JaspToQC.h"

#include "qcc/Dialect/Jasp/IR/Jasp.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Func/Transforms/FuncConversions.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/QC/IR/QCDialect.h"
#include "mlir/Dialect/QC/IR/QCOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Types.h"
#include "mlir/IR/ValueRange.h"
#include "mlir/Support/LLVM.h"
#include "mlir/Support/LogicalResult.h"
#include "mlir/Transforms/DialectConversion.h"

#include "llvm/Support/Casting.h"

#include <cassert>
#include <cstddef>
#include <optional>
#include <utility>

namespace qcc {
using namespace jasp;
using namespace mlir;
using namespace mlir::qc;

#define GEN_PASS_DEF_JASPTOQC
#include "qcc/Conversion/JaspToQC/JaspToQC.h.inc"

namespace {
/// Type converter for jasp-to-QC conversion, to be used
/// for op-conversions.
///
/// Handles type conversion between the jasp and QC dialects.
///  - The jasp qubit type is mapped to the QC qubit type.
///  - !jasp.QubitArray is mapped to memref<?x!qc.qubit>.
///  - !jasp.QuantumState is left intact.
///    TODO: This is a hack. If we delete the QuantumState
///    type here, conversion fails before any pattern is applied.
///    But if we leave it out, function signatures will not be
///    updated. Therefore, we need two separate type converters.
///
/// In addition, prevalent rank-zero-tensors `tensor<i64>` and `tensor<f64>`
/// are converted to plain values wherever possible.
class JaspToQCTypeConverter : public TypeConverter {
public:
  explicit JaspToQCTypeConverter(MLIRContext* ctx) {
    // Identity conversion for all types by default
    addConversion([](Type type) { return type; });

    addConversion([ctx](jasp::QubitType /*type*/) -> Type { return qc::QubitType::get(ctx); });
    addConversion([ctx](jasp::QubitArrayType /*type*/) -> Type {
      return MemRefType::get({ShapedType::kDynamic}, qc::QubitType::get(ctx));
    });

    addConversion([](mlir::RankedTensorType type) -> std::optional<mlir::Type> {
      if (type.getRank() == 0) {
        return type.getElementType();
      }
      return std::nullopt; // Leave multi-dimensional tensors alone
    });

    addTargetMaterialization(
        [](mlir::OpBuilder& builder, mlir::Type /*type*/, mlir::ValueRange inputs, mlir::Location loc) -> mlir::Value {
          if (inputs.size() != 1 || !llvm::isa<mlir::TensorType>(inputs[0].getType())) {
            return nullptr;
          }

          return mlir::tensor::ExtractOp::create(builder, loc, inputs[0], mlir::ValueRange{});
        });

    addSourceMaterialization([](mlir::OpBuilder& builder, mlir::RankedTensorType type, mlir::ValueRange inputs,
                                mlir::Location loc) -> mlir::Value {
      if (inputs.size() != 1 || !inputs[0].getType().isIntOrIndexOrFloat()) {
        return nullptr;
      }

      return {mlir::tensor::FromElementsOp::create(builder, loc, type, inputs[0])};
    });
  }
};

/// Type converter for jasp-to-QC conversion, to be
/// used in function signature conversions.
///
/// In addition to the base converter, !jasp.QuantumState is destroyed.
class QuantumStateEliminator final : public JaspToQCTypeConverter {
public:
  explicit QuantumStateEliminator(MLIRContext* ctx) : JaspToQCTypeConverter(ctx) {
    addConversion([](jasp::QuantumStateType /*type*/, SmallVectorImpl<Type>&) { return success(); });
  }
};

// TODO: add operation support: parity, barrier, slice, fuse, get_size, reset

/// Converts jasp.create_quantum_kernel by deleting it
///
/// The jasp.QuantumState is used for tracking state in the jasp dialect.
/// Since QC dialect operations are side-effecting, the initial state creation is dropped.
///
/// NOTE: For this to work, the IR must be ordered correctly at the start of this pass.
struct ConvertJaspCreateQuantumKernelOp final : OpConversionPattern<jasp::CreateQuantumKernelOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::CreateQuantumKernelOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {
    rewriter.eraseOp(op);
    return success();
  }
};

/// Converts jasp.create_qubits to memref.alloc
///
/// The jasp.QuantumState is dropped. The size tensor is extracted to an index
/// to allocate a memref of qubits.
///
/// Example transformation:
/// ```mlir
/// %q_arr, %state1 = jasp.create_qubits %index, %state0 : !jasp.QuantumState, tensor<i64> -> !jasp.QubitArray,
/// !jasp.QuantumState
/// ```
/// becomes:
/// ```mlir
/// %index_1 = arith.index_cast %index : i64 to index
/// %q_arr = memref.alloc(%index_1) : memref<?x!qc.qubit>
/// ```
struct ConvertJaspCreateQubitsOp final : OpConversionPattern<jasp::CreateQubitsOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::CreateQubitsOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    auto loc = op.getLoc();
    auto index = arith::IndexCastOp::create(rewriter, loc, rewriter.getIndexType(), adaptor.getAmount());
    auto memrefType = MemRefType::get({ShapedType::kDynamic}, qc::QubitType::get(getContext()));
    auto alloc = memref::AllocOp::create(rewriter, loc, cast<MemRefType>(memrefType), ValueRange{index});
    rewriter.replaceOpWithMultiple(op, {alloc.getResult(), ValueRange()});
    return success();
  }
};

/// Converts jasp.get_qubit to memref.load
///
/// The conversion is straightforward. Only the index type needs to be
/// converted.
///
/// Example transformation:
/// ```mlir
/// %q = jasp.get_qubit %q_arr, %i : !jasp.QubitArray, tensor<i64> -> !jasp.Qubit
/// ```
/// becomes:
/// ```mlir
/// %i_index = arith.index_cast %i : i64 to index
///  %q = memref.load %q_arr[%i_index] : memref<?x!qc.qubit>
/// ```
struct ConvertJaspGetQubitOp final : OpConversionPattern<jasp::GetQubitOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::GetQubitOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    auto loc = op.getLoc();
    auto indexTensor = adaptor.getPosition();

    auto index = arith::IndexCastOp::create(rewriter, loc, rewriter.getIndexType(), indexTensor);
    rewriter.replaceOpWithNewOp<memref::LoadOp>(op, adaptor.getQbArray(), ValueRange{index});

    return success();
  }
};

/// Converts jasp.consume_quantum_kernel op to arith.constant
///
/// We do not lower the functionality of returning a success value
/// for the kernel execution. A constant value of 1 is returned,
/// assuming a successful execution.
///
/// Example transformation:
/// ```mlir
/// %success = jasp.consume_quantum_kernel %state : !jasp.QuantumState -> tensor<i1>
/// ```
/// becomes:
/// ```mlir
/// %success = arith.constant dense<1> : tensor<i1>
/// ```
struct ConvertJaspConsumeQuantumKernelOp final : OpConversionPattern<jasp::ConsumeQuantumKernelOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::ConsumeQuantumKernelOp op, OpAdaptor /*adaptor*/,
                                ConversionPatternRewriter& rewriter) const override {

    auto trueAttr = rewriter.getBoolAttr(true);
    rewriter.replaceOpWithNewOp<arith::ConstantOp>(op, rewriter.getI1Type(), cast<TypedAttr>(trueAttr));

    return success();
  }
};

/// Converts a jasp gate to QC
///
/// Converts generic jasp.quantum_gate operations into specific QC dialect
/// operations based on the gate name string.
///
/// This pattern handles the extraction of parameters from tensors, the
/// mapping of target qubits, and the conversion of controlled gates into
/// `qc.ctrl` operations containing the base gate in their region.
///
/// Example:
/// ```mlir
/// %state_out = jasp.quantum_gate "h" (%q), %state_in : (!jasp.Qubit), !jasp.QuantumState -> !jasp.QuantumState
/// ```
/// becomes:
/// ```mlir
/// qc.h %q : !qc.qubit
/// ```
struct ConvertJaspQuantumGateOp final : OpConversionPattern<jasp::QuantumGateOp> {
  using OpConversionPattern<jasp::QuantumGateOp>::OpConversionPattern;

  /// Macro to attempt converting a jasp gate to a specific QC operation
#define TRY_CONVERT_GATE(NAME, OPTYPE, N_CONTROLS, N_TARGETS, N_PARAMS)                                                \
  if (gateName == (NAME)) {                                                                                            \
    return convertGate<OPTYPE>(op, adaptor, rewriter, std::make_index_sequence<N_CONTROLS>{},                          \
                               std::make_index_sequence<N_TARGETS>{}, std::make_index_sequence<N_PARAMS>{});           \
  }

  LogicalResult matchAndRewrite(jasp::QuantumGateOp op, jasp::QuantumGateOp::Adaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {

    auto gateName = op.getGateType();

    TRY_CONVERT_GATE("id", qc::IdOp, 0, 1, 0);
    TRY_CONVERT_GATE("gphase", qc::GPhaseOp, 0, 0, 1);
    TRY_CONVERT_GATE("x", qc::XOp, 0, 1, 0);
    TRY_CONVERT_GATE("y", qc::YOp, 0, 1, 0);
    TRY_CONVERT_GATE("z", qc::ZOp, 0, 1, 0);
    TRY_CONVERT_GATE("h", qc::HOp, 0, 1, 0);
    TRY_CONVERT_GATE("cx", qc::XOp, 1, 1, 0);
    TRY_CONVERT_GATE("cy", qc::YOp, 1, 1, 0);
    TRY_CONVERT_GATE("cz", qc::ZOp, 1, 1, 0);
    TRY_CONVERT_GATE("p", qc::POp, 0, 1, 1);
    TRY_CONVERT_GATE("cp", qc::POp, 1, 1, 1);
    TRY_CONVERT_GATE("rx", qc::RXOp, 0, 1, 1);
    TRY_CONVERT_GATE("ry", qc::RYOp, 0, 1, 1);
    TRY_CONVERT_GATE("rz", qc::RZOp, 0, 1, 1);
    TRY_CONVERT_GATE("crz", qc::RZOp, 1, 1, 1);
    TRY_CONVERT_GATE("s", qc::SOp, 0, 1, 0);
    TRY_CONVERT_GATE("s_dg", qc::SdgOp, 0, 1, 0);
    TRY_CONVERT_GATE("t", qc::TOp, 0, 1, 0);
    TRY_CONVERT_GATE("t_dg", qc::TdgOp, 0, 1, 0);
    TRY_CONVERT_GATE("sx", qc::SXOp, 0, 1, 0);
    TRY_CONVERT_GATE("swap", qc::SWAPOp, 0, 2, 0);
    TRY_CONVERT_GATE("rxx", qc::RXXOp, 0, 2, 1);
    TRY_CONVERT_GATE("rzz", qc::RZZOp, 0, 2, 1);
    TRY_CONVERT_GATE("xxyy", qc::XXPlusYYOp, 0, 2, 2);
    TRY_CONVERT_GATE("u3", qc::UOp, 0, 1, 3);

    // TODO: add multi-controlled gates

    return failure();
  }

#undef TRY_CONVERT_GATE

private:
  template <typename QCOp, std::size_t... controlOperandIndices, std::size_t... targetOperandIndices,
            std::size_t... paramOperandIndices>
  LogicalResult convertGate(jasp::QuantumGateOp op, jasp::QuantumGateOp::Adaptor adaptor,
                            ConversionPatternRewriter& rewriter,
                            std::index_sequence<controlOperandIndices...> /*unused*/,
                            std::index_sequence<targetOperandIndices...> /*unused*/,
                            std::index_sequence<paramOperandIndices...> /*unused*/) const {
    auto operands = adaptor.getGateOperands();
    const auto numControls = sizeof...(controlOperandIndices);
    const auto numTargets = sizeof...(targetOperandIndices);
    const auto numParams = sizeof...(paramOperandIndices);

    const auto targetIndexOffset = numControls;
    const auto paramIndexOffset = targetIndexOffset + numTargets;

    assert(operands.size() == numControls + numTargets + numParams && "Invalid number of gate operands");

    if constexpr (numControls == 0) {
      QCOp::create(rewriter, op.getLoc(), operands[targetOperandIndices]...,
                   operands[paramOperandIndices + paramIndexOffset]...);
    } else {
      qc::CtrlOp::create(rewriter, op.getLoc(), operands.take_front(numControls), [&]() {
        QCOp::create(rewriter, op.getLoc(), operands[targetOperandIndices + targetIndexOffset]...,
                     operands[paramOperandIndices + paramIndexOffset]...);
      });
    }

    rewriter.eraseOp(op);
    return success();
  }
};

/// Converts jasp.measure to qc.measure
///
/// Handles both single-qubit and qubit-array measurement:
///   - Single qubit: directly emits qc.measure
///   - Qubit array: iterates over all qubits with scf.for, measures each
///     individually, and packs the result bits into an i64.
///
/// Example (single qubit):
/// ```mlir
/// %measured, %state1 = jasp.measure %q, %state0 : !jasp.Qubit, !jasp.QuantumState -> tensor<i1>, !jasp.QuantumState
/// ```
/// becomes:
/// ```mlir
/// %measured = qc.measure %q : !qc.qubit -> i1
/// ```
struct ConvertJaspMeasureOp final : OpConversionPattern<jasp::MeasureOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::MeasureOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    auto loc = op.getLoc();
    Value measQOperand = adaptor.getMeasQ();
    Type measQType = measQOperand.getType();

    // single qubit measurement
    if (!isa<MemRefType>(measQType)) {
      return convertSingleQubitMeasurement(op, rewriter, loc, measQOperand);
    }

    return convertArrayMeasurement(op, rewriter, loc, measQOperand);
  }

private:
  LogicalResult convertSingleQubitMeasurement(jasp::MeasureOp op, ConversionPatternRewriter& rewriter, Location loc,
                                              Value qubit) const {
    Type resultType = typeConverter->convertType(op.getMeasRes().getType());
    assert(resultType && resultType.isIntOrIndex() && "resultType should not be null");

    auto measOp = qc::MeasureOp::create(rewriter, loc, qubit);
    Value bit = measOp.getResult();

    // If the result type is wider (e.g. i64), extend.
    if (!resultType.isInteger(1)) {
      bit = arith::ExtUIOp::create(rewriter, loc, resultType, bit);
    }

    rewriter.replaceOpWithMultiple(op, {bit, ValueRange()});
    return success();
  }

  LogicalResult convertArrayMeasurement(jasp::MeasureOp op, ConversionPatternRewriter& rewriter, Location loc,
                                        Value array) const {
    // TODO: Clean up if equivalent semantics become possible in qc.
    // As long as we don't have measurement to integers, we need to lower to
    // bit-fiddling here.

    auto resultType = typeConverter->convertType(op.getMeasRes().getType());
    assert(resultType && resultType.isInteger(64) && "only packing into i64 integers is supported");

    auto i64Type = rewriter.getI64Type();

    Value c0Index = arith::ConstantIndexOp::create(rewriter, loc, 0);
    Value c1Index = arith::ConstantIndexOp::create(rewriter, loc, 1);
    Value c0I64 = arith::ConstantOp::create(rewriter, loc, i64Type, cast<TypedAttr>(rewriter.getI64IntegerAttr(0)));

    Value size = memref::DimOp::create(rewriter, loc, array, c0Index);

    auto forOp = scf::ForOp::create(rewriter, loc, c0Index, size, c1Index, ValueRange{c0I64});

    rewriter.setInsertionPointToStart(forOp.getBody());
    Value iv = forOp.getInductionVar();
    Value acc = forOp.getRegionIterArg(0);

    Value qubit = memref::LoadOp::create(rewriter, loc, array, ValueRange{iv});
    auto measOp = qc::MeasureOp::create(rewriter, loc, qubit);
    Value bit = measOp.getResult();

    Value bitI64 = arith::ExtUIOp::create(rewriter, loc, i64Type, bit);
    Value ivI64 = arith::IndexCastOp::create(rewriter, loc, i64Type, iv);
    Value shifted = arith::ShLIOp::create(rewriter, loc, bitI64, ivI64);
    Value newAcc = arith::OrIOp::create(rewriter, loc, acc, shifted);

    scf::YieldOp::create(rewriter, loc, newAcc);

    rewriter.replaceOpWithMultiple(op, {forOp.getResult(0), ValueRange()});
    return success();
  }
};

/// Converts jasp.delete_qubits to memref.dealloc
///
/// Example transformation:
/// ```mlir
/// %state1 = jasp.delete_qubits %qubit_array, %state0 : !jasp.QubitArray, !jasp.QuantumState -> !jasp.QuantumState
/// ```
/// becomes:
/// ```mlir
/// memref.dealloc %qubit_array : memref<?x!qc.qubit>
/// ```
struct ConvertJaspDeleteQubitsOp final : OpConversionPattern<jasp::DeleteQubitsOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(jasp::DeleteQubitsOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    auto array = adaptor.getQubits();
    memref::DeallocOp::create(rewriter, op.getLoc(), array);
    rewriter.eraseOp(op);
    return success();
  }
};

/// Convert Rank-Zero Tensors to their wrapped types in `linalg.generic` operations.
/// Only operands are affected.
struct ConvertRankZeroTensorsInLinalg final : OpConversionPattern<linalg::GenericOp> {
  using OpConversionPattern::OpConversionPattern;

  LogicalResult matchAndRewrite(linalg::GenericOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter& rewriter) const override {
    SmallVector<AffineMap> newMaps = op.getIndexingMapsArray();
    for (auto it : llvm::enumerate(op.getInputs())) {
      if (isa<RankedTensorType>(it.value().getType()) &&
          llvm::cast<RankedTensorType>(it.value().getType()).getRank() == 0) {
        newMaps[it.index()] = rewriter.getMultiDimIdentityMap(0);
      }
    }

    auto newOp = linalg::GenericOp::create(rewriter, op.getLoc(), op.getResultTypes(), adaptor.getInputs(),
                                           adaptor.getOutputs(), newMaps, op.getIteratorTypesArray());

    rewriter.inlineRegionBefore(op.getRegion(), newOp.getRegion(), newOp.getRegion().begin());

    rewriter.replaceOp(op, newOp.getResults());
    return success();
  }
};

struct JaspToQC final : impl::JaspToQCBase<JaspToQC> {
  using JaspToQCBase::JaspToQCBase;

protected:
  void runOnOperation() override {
    MLIRContext* context = &getContext();
    auto* module = getOperation();

    ConversionTarget target(*context);
    RewritePatternSet patterns(context);
    const JaspToQCTypeConverter typeConverter(context);
    QuantumStateEliminator stateDestroyer(context);

    target.addIllegalDialect<JaspDialect>();
    target.addLegalDialect<QCDialect, memref::MemRefDialect, arith::ArithDialect, func::FuncDialect,
                           linalg::LinalgDialect, scf::SCFDialect>();

    patterns.add<ConvertJaspCreateQuantumKernelOp, ConvertJaspConsumeQuantumKernelOp, ConvertJaspCreateQubitsOp,
                 ConvertJaspGetQubitOp, ConvertJaspQuantumGateOp, ConvertJaspMeasureOp, ConvertJaspDeleteQubitsOp,
                 ConvertRankZeroTensorsInLinalg>(typeConverter, context);

    target.addDynamicallyLegalOp<func::FuncOp>([&](func::FuncOp op) {
      auto islegal = stateDestroyer.isSignatureLegal(op.getFunctionType());
      return islegal;
    });

    populateAnyFunctionOpInterfaceTypeConversionPattern(patterns, stateDestroyer);

    populateReturnOpTypeConversionPattern(patterns, stateDestroyer);
    target.addDynamicallyLegalOp<func::ReturnOp>([&](const func::ReturnOp op) { return stateDestroyer.isLegal(op); });

    populateCallOpTypeConversionPattern(patterns, stateDestroyer);
    target.addDynamicallyLegalOp<func::CallOp>([&](const func::CallOp op) { return stateDestroyer.isLegal(op); });

    populateBranchOpInterfaceTypeConversionPattern(patterns, stateDestroyer);

    scf::populateSCFStructuralTypeConversionsAndLegality(stateDestroyer, patterns, target);

    if (failed(applyPartialConversion(module, target, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};
} // namespace
} // namespace qcc
