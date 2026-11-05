// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// expected-error @below {{'hlep.halo' function must not have zero arguments; use '!hlep.unit' instead}}
func.func private @no_args() -> !hlep.unit attributes { hlep.halo = #hlep.halo }

// -----

// expected-error @below {{'hlep.halo' function must not have zero results; use '!hlep.unit' instead}}
func.func private @no_results(%halo: !hlep.unit) attributes { hlep.halo = #hlep.halo }
