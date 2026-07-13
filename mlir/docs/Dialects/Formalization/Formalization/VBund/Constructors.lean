/-
  # Type Constructors for Vector Bundles

  The four type constructors of the PrelimHLEP type system:
  * Cartesian product `×`  (fiberwise direct sum; avoided in the IR),
  * Linear product `⊗`     (fiberwise tensor product; used implicitly),
  * Coproduct `⊔`          (disjoint union of bases and fibers),
  * Linearization `Lin`    (direct sum of fibers over the singleton base).

  Each constructor is accompanied by its unit and the algebraic instances
  on its fibers. Morphism-level structure (projections, universal property)
  is deferred to a later file.

  Note on `Lin`: the direct sum of fibers is modeled as `DFinsupp`
  (dependent functions with finite support, written `Π₀ (w : W), H_w`),
  which is Mathlib's standard type for the direct sum of a family of
  modules over a plain (non-semiring) index type. The summand inclusion is
  `DFinsupp.lsingle`, which requires `DecidableEq` on the index type; this
  is supplied automatically for finite types with decidable equality.
-/

import Mathlib
import Formalization.VBund.Basic
import Formalization.VBund.Hom

noncomputable section

open scoped TensorProduct Classical

namespace Formalization

/-! ## Cartesian product (fiberwise direct sum) -/

section cartProdDef

variable (E E' : VBund)

/-- The Cartesian product: the base is the product of bases, and the fiber
is the direct sum (here: product) of the fibers. This represents independent
quantum systems and is *avoided* in the IR. -/
abbrev cartProd : VBund :=
  { base := E.base × E'.base,
    fiber := fun (w, w') => (E.fiber w) × (E'.fiber w') }

instance [Fintype E.base] [Fintype E'.base] :
    Fintype (cartProd E E').base := inferInstanceAs (Fintype (E.base × E'.base))

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
    (w : (cartProd E E').base) : AddCommGroup ((cartProd E E').fiber w) := by
  dsimp [cartProd]
  infer_instance

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
    (w : (cartProd E E').base) : Module ℂ ((cartProd E E').fiber w) := by
  dsimp [cartProd]
  infer_instance

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)] :
    ∀ w, AddCommGroup ((cartProd E E').fiber w) := by
  intro w; change AddCommGroup (E.fiber w.1 × E'.fiber w.2); infer_instance

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)] :
    ∀ w, Module ℂ ((cartProd E E').fiber w) := by
  intro w; change Module ℂ (E.fiber w.1 × E'.fiber w.2); infer_instance

end cartProdDef

/-- The unit of the Cartesian product: the zero bundle over the singleton. -/
abbrev cartProdUnit : VBund :=
  { base := PUnit, fiber := fun _ => PUnit }

instance : ∀ w, AddCommGroup (cartProdUnit.fiber w) :=
  fun _ => inferInstanceAs (AddCommGroup PUnit)
instance : ∀ w, Module ℂ (cartProdUnit.fiber w) :=
  fun _ => inferInstanceAs (Module ℂ PUnit)

/-! ### Unit isomorphisms for the Cartesian product -/

section cartProdUnitLemmas

variable (E : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]

instance : ∀ w, AddCommGroup ((cartProd E cartProdUnit).fiber w) :=
  fun w => inferInstanceAs (AddCommGroup (E.fiber w.1 × PUnit))
instance : ∀ w, Module ℂ ((cartProd E cartProdUnit).fiber w) :=
  fun w => inferInstanceAs (Module ℂ (E.fiber w.1 × PUnit))
instance : ∀ w, AddCommGroup ((cartProd cartProdUnit E).fiber w) :=
  fun w => inferInstanceAs (AddCommGroup (PUnit × E.fiber w.2))
instance : ∀ w, Module ℂ ((cartProd cartProdUnit E).fiber w) :=
  fun w => inferInstanceAs (Module ℂ (PUnit × E.fiber w.2))

/-- Right unitor: `E × 1 ≅ E` via projection onto `E`. -/
def cartProd.rightUnitor : VBundIso (cartProd E cartProdUnit) E :=
  { hom :=
      { cl := λ (w, ()) => w
        lin := λ (w, ()) => by
          dsimp [cartProd, cartProdUnit, zeroBundle]
          exact LinearMap.fst ℂ (E.fiber w) PUnit }
    inv :=
      { cl := λ w => (w, ())
        lin := λ w => by
          dsimp [cartProd, cartProdUnit, zeroBundle]
          exact LinearMap.inl ℂ (E.fiber w) PUnit }
    left_inv := by
      refine VBundHom.ext ?_ ?_
      · ext x; cases x; rfl
      · intro x; cases x; apply heq_of_eq; rfl
    right_inv := by
      refine VBundHom.ext ?_ ?_
      · ext w; rfl
      · intro w; apply heq_of_eq; rfl
  }

/-- Left unitor: `1 × E ≅ E` via projection onto `E`. -/
def cartProd.leftUnitor : VBundIso (cartProd cartProdUnit E) E :=
  { hom :=
      { cl := λ ((), w) => w
        lin := λ ((), w) => by
          dsimp [cartProd, cartProdUnit, zeroBundle]
          exact LinearMap.snd ℂ PUnit (E.fiber w) }
    inv :=
      { cl := λ w => ((), w)
        lin := λ w => by
          dsimp [cartProd, cartProdUnit, zeroBundle]
          exact LinearMap.inr ℂ PUnit (E.fiber w) }
    left_inv := by
      refine VBundHom.ext ?_ ?_
      · ext x; cases x; rfl
      · intro x; cases x; apply heq_of_eq; rfl
    right_inv := by
      refine VBundHom.ext ?_ ?_
      · ext w; rfl
      · intro w; apply heq_of_eq; rfl
  }

end cartProdUnitLemmas

/-! ## Linear product (fiberwise tensor product) -/

section linProdDef

variable (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
  [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]

/-- The linear (tensor) product: the base is the product of bases, and the
fiber is the tensor product of the fibers. This is the product used
implicitly throughout the IR in quantum context. -/
abbrev linProd : VBund :=
  { base := E.base × E'.base,
    fiber := fun (w, w') => TensorProduct ℂ (E.fiber w) (E'.fiber w') }

instance [Fintype E.base] [Fintype E'.base] :
    Fintype (linProd E E').base := inferInstanceAs (Fintype (E.base × E'.base))

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
    (w : (linProd E E').base) : AddCommGroup ((linProd E E').fiber w) := by
  dsimp [linProd]
  infer_instance

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
    (w : (linProd E E').base) : Module ℂ ((linProd E E').fiber w) := by
  dsimp [linProd]
  infer_instance

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)] :
    ∀ w, AddCommGroup ((linProd E E').fiber w) := by
  intro w; change AddCommGroup (TensorProduct ℂ (E.fiber w.1) (E'.fiber w.2)); infer_instance

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)] :
    ∀ w, Module ℂ ((linProd E E').fiber w) := by
  intro w; change Module ℂ (TensorProduct ℂ (E.fiber w.1) (E'.fiber w.2)); infer_instance

end linProdDef

/-- The unit of the linear product: ℂ over the singleton. -/
abbrev linProdUnit : VBund :=
  { base := PUnit, fiber := fun _ => ℂ }

instance : ∀ w, AddCommGroup (linProdUnit.fiber w) :=
  fun _ => inferInstanceAs (AddCommGroup ℂ)
instance : ∀ w, Module ℂ (linProdUnit.fiber w) :=
  fun _ => inferInstanceAs (Module ℂ ℂ)

/-! ### Unit isomorphisms for the linear product -/

section linProdUnitLemmas

variable (E : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]

instance : ∀ w, AddCommGroup ((linProd E linProdUnit).fiber w) :=
  fun w => inferInstanceAs (AddCommGroup (TensorProduct ℂ (E.fiber w.1) ℂ))
instance : ∀ w, Module ℂ ((linProd E linProdUnit).fiber w) :=
  fun w => inferInstanceAs (Module ℂ (TensorProduct ℂ (E.fiber w.1) ℂ))
instance : ∀ w, AddCommGroup ((linProd linProdUnit E).fiber w) :=
  fun w => inferInstanceAs (AddCommGroup (TensorProduct ℂ ℂ (E.fiber w.2)))
instance : ∀ w, Module ℂ ((linProd linProdUnit E).fiber w) :=
  fun w => inferInstanceAs (Module ℂ (TensorProduct ℂ ℂ (E.fiber w.2)))

/-- Right unitor: `E ⊗ 1 ≅ E` using `TensorProduct.rid`. -/
def linProd.rightUnitor : VBundIso (linProd E linProdUnit) E :=
  { hom :=
      { cl := λ (w, ()) => w
        lin := λ (w, ()) => by
          dsimp [linProd, linProdUnit, haloBundle]
          exact (TensorProduct.rid ℂ (E.fiber w)).toLinearMap }
    inv :=
      { cl := λ w => (w, ())
        lin := λ w => by
          dsimp [linProd, linProdUnit, haloBundle]
          exact (TensorProduct.rid ℂ (E.fiber w)).symm.toLinearMap }
    left_inv := by
      refine VBundHom.ext ?_ ?_
      · ext x; cases x; rfl
      · intro x; cases x; apply heq_of_eq; ext x; simp
    right_inv := by
      refine VBundHom.ext ?_ ?_
      · ext w; rfl
      · intro w; apply heq_of_eq; ext x; simp
  }

/-- Left unitor: `1 ⊗ E ≅ E` using `TensorProduct.lid`. -/
def linProd.leftUnitor : VBundIso (linProd linProdUnit E) E :=
  { hom :=
      { cl := λ ((), w) => w
        lin := λ ((), w) => by
          dsimp [linProd, linProdUnit, haloBundle]
          exact (TensorProduct.lid ℂ (E.fiber w)).toLinearMap }
    inv :=
      { cl := λ w => ((), w)
        lin := λ w => by
          dsimp [linProd, linProdUnit, haloBundle]
          exact (TensorProduct.lid ℂ (E.fiber w)).symm.toLinearMap }
    left_inv := by
      refine VBundHom.ext ?_ ?_
      · ext x; cases x; rfl
      · intro x; cases x; apply heq_of_eq; ext x; simp
    right_inv := by
      refine VBundHom.ext ?_ ?_
      · ext w; rfl
      · intro w; apply heq_of_eq; ext x; simp
  }

end linProdUnitLemmas

/-! ## Coproduct (disjoint union) -/


section coprodDef

variable (E E' : VBund)

/-- The coproduct: the base is the disjoint union of bases, and the fiber
over `Sum.inl w` (resp. `Sum.inr w'`) is `E.fiber w` (resp. `E'.fiber w'`). -/
abbrev coprod : VBund :=
  { base := E.base ⊕ E'.base,
    fiber := fun ww' => match ww' with
      | Sum.inl w => E.fiber w
      | Sum.inr w' => E'.fiber w' }

instance [Fintype E.base] [Fintype E'.base] :
    Fintype (coprod E E').base := inferInstanceAs (Fintype (E.base ⊕ E'.base))

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
    (w : (coprod E E').base) : AddCommGroup ((coprod E E').fiber w) := by
  cases w
  · change AddCommGroup (E.fiber _); infer_instance
  · change AddCommGroup (E'.fiber _); infer_instance

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
    (w : (coprod E E').base) : Module ℂ ((coprod E E').fiber w) := by
  cases w
  · change Module ℂ (E.fiber _); infer_instance
  · change Module ℂ (E'.fiber _); infer_instance

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)] :
    ∀ w, AddCommGroup ((coprod E E').fiber w) := by
  intro w
  match w with
  | Sum.inl w' => change AddCommGroup (E.fiber w'); infer_instance
  | Sum.inr w' => change AddCommGroup (E'.fiber w'); infer_instance

instance (E E' : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)] :
    ∀ w, Module ℂ ((coprod E E').fiber w) := by
  intro w
  match w with
  | Sum.inl w' => change Module ℂ (E.fiber w'); infer_instance
  | Sum.inr w' => change Module ℂ (E'.fiber w'); infer_instance

end coprodDef

/-- The initial object of the coproduct: the empty bundle over the empty
base. Since `Empty` has no elements, the fiber type is irrelevant; `PUnit`
is a convenient concrete choice that provides all necessary instances. -/
abbrev coprodInit : VBund :=
  { base := Empty, fiber := fun _ => PUnit }

instance : Fintype (coprodInit).base := inferInstanceAs (Fintype Empty)

instance (w : coprodInit.base) : AddCommGroup (coprodInit.fiber w) :=
  Empty.elim w

instance (w : coprodInit.base) : Module ℂ (coprodInit.fiber w) :=
  Empty.elim w

instance : ∀ w, AddCommGroup (coprodInit.fiber w) :=
  fun w => Empty.elim w

instance : ∀ w, Module ℂ (coprodInit.fiber w) :=
  fun w => Empty.elim w

/-! ### Initial object property of `coprodInit` -/

section coprodInitLemmas

variable (E : VBund) [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]

/-- There is a unique morphism from the empty bundle to any bundle `E`. -/
noncomputable def coprodInit.to (E : VBund)
    [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)] : VBundHom coprodInit E where
  cl := fun w => Empty.elim w
  lin := fun w => Empty.elim w

/-- Uniqueness: any two morphisms from `coprodInit` to `E` are equal. -/
theorem coprodInit.hom_unique (f g : VBundHom coprodInit E) : f = g := by
  apply VBundHom.ext
  · ext w; exact Empty.elim w
  · intro w; exact Empty.elim w

end coprodInitLemmas

/-! ## Linearization (direct sum over the singleton base) -/

section linDef

variable (E : VBund) [Fintype E.base] [DecidableEq E.base]
  [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]

/-- The linearization functor `Lin`: collapses the base to the singleton and
takes the direct sum of all fibers. This turns a mixed type into a purely
linear type.

  `Lin [H_• ↓ W] = [⊕_{w:W} H_w ↓ *]`

The direct sum is modeled as `DFinsupp` (`Π₀`), Mathlib's type for the
direct sum of a family of modules over a plain index type. The operation is
idempotent: `Lin (Lin E) ≅ Lin E` (since `Lin E` already has singleton
base).

Declared as an `abbrev` with anonymous-constructor syntax. The
`variable (E : VBund)` in this section makes `E` an explicit parameter of
`lin`, which is essential for the `abbrev` reduction of the fiber projection
to work: without it, `(lin E).fiber ()` does not reduce to
`Π₀ (w : E.base), E.fiber w` and type-class resolution fails. -/
abbrev lin : VBund :=
  { base := PUnit, fiber := fun _ => Π₀ (w : E.base), E.fiber w }

instance : Fintype (lin E).base :=
  inferInstanceAs (Fintype PUnit)

/-- The halo embedding `η : E → Lin E` is the unit of the `Lin ⊣ U`
adjunction (see `LNL.lean` for the categorical framing). The base map is
`W → *`; the fiber map `H_w → ⊕ H` is the canonical inclusion of the
`w`-th summand via `DFinsupp.lsingle`. -/
def lin.unit : VBundHom E (lin E) where
  cl := fun _ => ()
  lin := fun w => DFinsupp.lsingle (R := ℂ) w

end linDef

end Formalization
