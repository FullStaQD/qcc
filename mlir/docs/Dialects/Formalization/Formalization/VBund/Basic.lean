/-
  # Vector Bundles over Finite Sets

  The core denotational semantic model of the PrelimHLEP dialect: a type is a
  finite-dimensional ℂ-vector bundle over a finite set.

  A `VBund` consists of
  * a finite base `base`,
  * a `base`-indexed family of finite-dimensional ℂ-vector spaces `fiber`,
  bundled together. We do not impose a topology or local-triviality
  condition: in the finite/discrete setting every bundle is trivially locally
  trivial, and the only structure that matters is the indexed family.

  Because the fiber type depends on the base, the algebraic structure on the
  fibers is supplied by external `instance` declarations (one per concrete
  bundle). This is the standard Mathlib idiom for dependent bundled data.

  This file defines the bare structure plus a few derived notions
  (dimension, the zero/terminal bundle, the halo, classical and linear
  embeddings). Constructors (products, coproducts, linearization) live in
  `Constructors.lean`; morphisms live in `Hom.lean`.
-/

import Mathlib

noncomputable section

open scoped TensorProduct

namespace Formalization

/-- A type-indexed family of types `(base, fiber)`.

Intended to be instantiated as a finite-dimensional ℂ-vector bundle over a
finite set, with the algebraic structure (finiteness of the base,
module/f.d. structure on each fiber) supplied externally via typeclass
instances per concrete bundle.

Both `base` and `fiber` live in `Type` (universe 1) to match `ℂ` and avoid
universe mismatches when forming the direct sum (`DFinsupp`) of the fibers. -/
structure VBund where
  /-- The (finite) classical base space. -/
  base : Type
  /-- The fiber over a base point. -/
  fiber : base → Type

/-- The dimension of the total (direct-sum) fiber space of a `VBund`. -/
def VBund.totalDim (E : VBund) [Fintype E.base]
    [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, FiniteDimensional ℂ (E.fiber w)] : ℕ :=
  ∑ w, Module.finrank ℂ (E.fiber w)

/-- The zero bundle over a base: every fiber is the trivial (one-element)
module. -/
def zeroBundle (W : Type) : VBund where
  base := W
  fiber := fun _ => PUnit

instance (W : Type) [Fintype W] : Fintype (zeroBundle W).base :=
  inferInstanceAs (Fintype W)
instance (W : Type) [Fintype W] (w : W) :
    AddCommGroup ((zeroBundle W).fiber w) :=
  inferInstanceAs (AddCommGroup PUnit)
instance (W : Type) [Fintype W] (w : W) :
    Module ℂ ((zeroBundle W).fiber w) :=
  inferInstanceAs (Module ℂ PUnit)
instance (W : Type) [Fintype W] (w : W) :
    FiniteDimensional ℂ ((zeroBundle W).fiber w) :=
  inferInstanceAs (FiniteDimensional ℂ PUnit)
instance (W : Type) [Fintype W] : ∀ w, AddCommGroup ((zeroBundle W).fiber w) :=
  fun _ => inferInstanceAs (AddCommGroup PUnit)
instance (W : Type) [Fintype W] : ∀ w, Module ℂ ((zeroBundle W).fiber w) :=
  fun _ => inferInstanceAs (Module ℂ PUnit)

/-- The "linear halo" bundle `ℂ × W`: a classical set `W` equipped with the
tensor unit ℂ as fiber. This is *not* a qubit type — it is a bit with a
quantum phase. -/
def haloBundle (W : Type) : VBund where
  base := W
  fiber := fun _ => ℂ

instance (W : Type) [Fintype W] : Fintype (haloBundle W).base :=
  inferInstanceAs (Fintype W)
instance (W : Type) [Fintype W] (w : W) :
    AddCommGroup ((haloBundle W).fiber w) :=
  inferInstanceAs (AddCommGroup ℂ)
instance (W : Type) [Fintype W] (w : W) :
    Module ℂ ((haloBundle W).fiber w) :=
  inferInstanceAs (Module ℂ ℂ)
instance (W : Type) [Fintype W] (w : W) :
    FiniteDimensional ℂ ((haloBundle W).fiber w) :=
  inferInstanceAs (FiniteDimensional ℂ ℂ)
instance (W : Type) [Fintype W] : ∀ w, AddCommGroup ((haloBundle W).fiber w) :=
  fun _ => inferInstanceAs (AddCommGroup ℂ)
instance (W : Type) [Fintype W] : ∀ w, Module ℂ ((haloBundle W).fiber w) :=
  fun _ => inferInstanceAs (Module ℂ ℂ)

/-- A purely classical type `W` is the zero bundle over `W`. -/
def classicalBundle (W : Type) : VBund := zeroBundle W

/-- A purely linear type `H` (a vector space) is the bundle over the
singleton with fiber `H`. -/
def linearBundle (H : Type) : VBund where
  base := PUnit
  fiber := fun _ => H

instance (H : Type) [Fintype H] : Fintype (linearBundle H).base :=
  inferInstanceAs (Fintype PUnit)
instance (H : Type) [AddCommGroup H] (w : PUnit) :
    AddCommGroup ((linearBundle H).fiber w) :=
  inferInstanceAs (AddCommGroup H)
instance (H : Type) [AddCommGroup H] [Module ℂ H] (w : PUnit) :
    AddCommMonoid ((linearBundle H).fiber w) :=
  inferInstanceAs (AddCommMonoid H)
instance (H : Type) [AddCommGroup H] [Module ℂ H] (w : PUnit) :
    Module ℂ ((linearBundle H).fiber w) :=
  inferInstanceAs (Module ℂ H)
instance (H : Type) [AddCommGroup H] [Module ℂ H]
    [FiniteDimensional ℂ H] (w : PUnit) :
    FiniteDimensional ℂ ((linearBundle H).fiber w) :=
  inferInstanceAs (FiniteDimensional ℂ H)

end Formalization
