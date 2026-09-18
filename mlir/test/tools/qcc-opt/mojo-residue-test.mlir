// RUN: qcc-opt %s --allow-unregistered-dialect --mlir-very-unsafe-disable-verifier-on-parsing --mojo-residue-to-std | FileCheck %s

// The input below is captured output, not a hand-written imitation of it:
// `kgen --elaborate -S -O1 -mlir-print-op-generic` on `mojo/spikes/s2residue.mojo`,
// with the module attribute dictionary (Mojo's build environment: target
// triple, features, optimization level) removed, since it is this machine's
// and nothing to do with the residue. Locations are left off here to keep the
// file readable; that they reach qcc intact is what `test/mojo/` checks.
//
// Re-capture it the same way after changing the eDSL library or picking up a
// newer Mojo.


// CNOT, then a measurement of each qubit. The target is moved into the body
// and flipped there, which is an `scf.if` with a `!prelimhlep.lin<i1>`
// result; the carry-out split arrives as real operand segments, because the
// fork registers the dialect and writes the property itself.
// CHECK-LABEL: func.func @cx_pair(
// CHECK-SAME:      %[[C:.*]]: !prelimhlep.lin<i1>, %[[T:.*]]: !prelimhlep.lin<i1>) -> i1
// The kernel is `@export`ed, so it is also marked as a starting point of a
// quantum program; that is what the QIR lowering looks for, in place of the
// JASP path's `@main` naming convention.
// CHECK-SAME:      attributes {prelimhlep.halo = #prelimhlep.halo, qcc.entry_point}
// CHECK:         %[[TRUE:.*]] = arith.constant true
// CHECK:         %[[OUT:.*]]:2 = prelimhlep.lin (%[[CB:.*]] : i1 from %[[C]] : !prelimhlep.lin<i1>)
// CHECK:           %[[NT:.*]] = scf.if %[[CB]] -> (!prelimhlep.lin<i1>) {
// CHECK:             %[[XT:.*]] = prelimhlep.lin (%[[TB:.*]] : i1 from %[[T]] : !prelimhlep.lin<i1>)
// CHECK:               %[[FLIP:.*]] = arith.xori %[[TB]], %[[TRUE]] : i1
// CHECK:               prelimhlep.output (%[[FLIP]] : i1)
// CHECK:             scf.yield %[[XT]]
// CHECK:           } else {
// CHECK:             scf.yield %[[T]]
// CHECK:           }
// CHECK:           prelimhlep.output (%[[CB]] : i1) carrying (%[[NT]] : !prelimhlep.lin<i1>)
// CHECK:         prelimhlep.lin (%{{.*}} : i1 from %[[OUT]]#0
// CHECK:         prelimhlep.lin (%{{.*}} : i1 from %[[OUT]]#1
// CHECK:         arith.select

// A classical helper: no linear type anywhere, so no halo tag. Signedness
// lives on the Mojo dtype, so `pop.cmp lt` on `ui4` is `ult`. The `10` is
// printed as -6 because a builtin `i4` is signless and prints signed.
// CHECK-LABEL: func.func @classify(
// CHECK-NOT:     prelimhlep.halo
// CHECK:         %[[THREE:.*]] = arith.constant 3 : i4
// CHECK:         %[[TEN:.*]] = arith.constant -6 : i4
// CHECK:         arith.cmpi eq, %{{.*}}, %[[TEN]] : i4
// CHECK:         arith.cmpi ult, %{{.*}}, %[[THREE]] : i4

// Widening, shifting and narrowing, all by dtype.
// CHECK-LABEL: func.func @widen(
// CHECK:         arith.extui %{{.*}} : i1 to i32
// CHECK:         arith.trunci %{{.*}} : i32 to i4
// CHECK:         arith.shli
// CHECK:         arith.shrui

"builtin.module"() ({
  "kgen.func"() <{LLVMArgMetadata = [], LLVMMetadata = {}, crossDeviceCaptures = #M<strings[]>, decorators = #kgen<decorators[]>, exportKind = #kgen.export<exported>, funcTypeGenerator = !kgen.generator<(!prelimhlep.lin<i1> owned, !prelimhlep.lin<i1> owned) cabi -> !kgen.scalar<bool>>, inlineLevel = 0 : i32, sym_name = "cx_pair"}> ({
  ^bb0(%arg3: !prelimhlep.lin<i1>, %arg4: !prelimhlep.lin<i1>):
    %12 = "kgen.param.constant"() <{value = #kgen<simd true> : !kgen.scalar<bool>}> : () -> !kgen.scalar<bool>
    %13:2 = "prelimhlep.lin"(%arg3) ({
    ^bb0(%arg7: i1):
      %19 = "pop.cast_from_builtin"(%arg7) : (i1) -> !kgen.scalar<bool>
      %20 = "hlcf.if"(%19) ({
        %21 = "prelimhlep.lin"(%arg4) ({
        ^bb0(%arg8: i1):
          %22 = "pop.cast_from_builtin"(%arg8) : (i1) -> !kgen.scalar<bool>
          %23 = "pop.simd.xor"(%22, %12) : (!kgen.scalar<bool>, !kgen.scalar<bool>) -> !kgen.scalar<bool>
          %24 = "pop.cast_to_builtin"(%23) : (!kgen.scalar<bool>) -> i1
          "prelimhlep.output"(%24) <{operandSegmentSizes = array<i32: 1, 0>}> : (i1) -> ()
        }) : (!prelimhlep.lin<i1>) -> !prelimhlep.lin<i1>
        "hlcf.yield"(%21) : (!prelimhlep.lin<i1>) -> ()
      }, {
        "hlcf.yield"(%arg4) : (!prelimhlep.lin<i1>) -> ()
      }) : (!kgen.scalar<bool>) -> !prelimhlep.lin<i1>
      "prelimhlep.output"(%arg7, %20) <{operandSegmentSizes = array<i32: 1, 1>}> : (i1, !prelimhlep.lin<i1>) -> ()
    }) : (!prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>, !prelimhlep.lin<i1>)
    %14 = "prelimhlep.lin"(%13#0) ({
    ^bb0(%arg6: i1):
      "prelimhlep.output"(%arg6) <{operandSegmentSizes = array<i32: 0, 1>}> : (i1) -> ()
    }) : (!prelimhlep.lin<i1>) -> i1
    %15 = "pop.cast_from_builtin"(%14) : (i1) -> !kgen.scalar<bool>
    %16 = "prelimhlep.lin"(%13#1) ({
    ^bb0(%arg5: i1):
      "prelimhlep.output"(%arg5) <{operandSegmentSizes = array<i32: 0, 1>}> : (i1) -> ()
    }) : (!prelimhlep.lin<i1>) -> i1
    %17 = "pop.cast_from_builtin"(%16) : (i1) -> !kgen.scalar<bool>
    %18 = "pop.select"(%15, %17, %15) : (!kgen.scalar<bool>, !kgen.scalar<bool>, !kgen.scalar<bool>) -> !kgen.scalar<bool>
    "kgen.return"(%18) : (!kgen.scalar<bool>) -> ()
  }) : () -> ()
  "kgen.func"() <{LLVMArgMetadata = [], LLVMMetadata = {}, crossDeviceCaptures = #M<strings[]>, decorators = #kgen<decorators[]>, exportKind = #kgen.export<exported>, funcTypeGenerator = !kgen.generator<(!kgen.scalar<ui4>) cabi -> !kgen.scalar<bool>>, inlineLevel = 0 : i32, sym_name = "classify"}> ({
  ^bb0(%arg2: !kgen.scalar<ui4>):
    %6 = "kgen.param.constant"() <{value = #kgen<simd 3> : !kgen.scalar<ui4>}> : () -> !kgen.scalar<ui4>
    %7 = "kgen.param.constant"() <{value = #kgen<simd 10> : !kgen.scalar<ui4>}> : () -> !kgen.scalar<ui4>
    %8 = "kgen.param.constant"() <{value = #kgen<simd true> : !kgen.scalar<bool>}> : () -> !kgen.scalar<bool>
    %9 = "pop.cmp"(%arg2, %7) <{pred = #kgen<cmp_pred eq>}> : (!kgen.scalar<ui4>, !kgen.scalar<ui4>) -> !kgen.scalar<bool>
    %10 = "pop.cmp"(%arg2, %6) <{pred = #kgen<cmp_pred lt>}> : (!kgen.scalar<ui4>, !kgen.scalar<ui4>) -> !kgen.scalar<bool>
    %11 = "pop.select"(%9, %8, %10) : (!kgen.scalar<bool>, !kgen.scalar<bool>, !kgen.scalar<bool>) -> !kgen.scalar<bool>
    "kgen.return"(%11) : (!kgen.scalar<bool>) -> ()
  }) : () -> ()
  "kgen.func"() <{LLVMArgMetadata = [], LLVMMetadata = {}, crossDeviceCaptures = #M<strings[]>, decorators = #kgen<decorators[]>, exportKind = #kgen.export<exported>, funcTypeGenerator = !kgen.generator<(!kgen.scalar<bool>, !kgen.scalar<ui4>) cabi -> !kgen.scalar<ui4>>, inlineLevel = 0 : i32, sym_name = "widen"}> ({
  ^bb0(%arg0: !kgen.scalar<bool>, %arg1: !kgen.scalar<ui4>):
    %0 = "pop.cast_to_builtin"(%arg0) : (!kgen.scalar<bool>) -> i1
    %1 = "pop.cast_from_builtin"(%0) : (i1) -> !kgen.scalar<ui1>
    %2 = "pop.cast"(%1) <{fastmathFlags = #pop<fmf fast>}> : (!kgen.scalar<ui1>) -> !kgen.scalar<ui32>
    %3 = "pop.cast"(%2) <{fastmathFlags = #pop<fmf fast>}> : (!kgen.scalar<ui32>) -> !kgen.scalar<ui4>
    %4 = "pop.shl"(%3, %arg1) : (!kgen.scalar<ui4>, !kgen.scalar<ui4>) -> !kgen.scalar<ui4>
    %5 = "pop.shr"(%4, %arg1) : (!kgen.scalar<ui4>, !kgen.scalar<ui4>) -> !kgen.scalar<ui4>
    "kgen.return"(%5) : (!kgen.scalar<ui4>) -> ()
  }) : () -> ()
}) : () -> ()
