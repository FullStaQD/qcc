// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// expected-error @below {{'prelimhlep.halo' function must not have zero arguments; use '!prelim_hlep.unit' instead}}
func.func private @no_args() -> !prelimhlep.unit attributes { prelimhlep.halo = #prelimhlep.halo }

// -----

// expected-error @below {{'prelimhlep.halo' function must not have zero results; use '!prelim_hlep.unit' instead}}
func.func private @no_results(%halo: !prelimhlep.unit) attributes { prelimhlep.halo = #prelimhlep.halo }
