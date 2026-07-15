/-
  # Measurement Result Sets and the Compatibility Relation

  This file formalizes **Layer 2** of the denotational semantics of the
  PrelimHLEP dialect: the pure finite-set-theory of measurement results.

  Given a (partially linearized) morphism `f` with classical part
  `f_cl : W × W' → V × V'`, the *measurement result set* `M(f)` is the image
  of the map

  ```
  κ_f : W → (W' → V'),   κ_f(w) = (w' ↦ pr_{V'}(f_cl(w, w')))
  ```

  i.e. the set of distinct "classical residue functions" `W' → V'` that arise
  as the left base point `w : W` varies. There is a canonical surjection

  ```
  π_f : W ↠ M(f)
  ```

  sending `w` to `κ_f(w)` (viewed as an element of the image), and a canonical
  injection `ι_f : M(f) ↪ (W' → V')` (the subtype inclusion).

  For composable morphisms `f` and `g`, we define a *compatibility relation*

  ```
  (φ, ψ) ~ ρ  ⟺  ∃ w : W, ∃ w' : W',
                    π_f(w) = φ  ∧  π_g(f_V(w, w')) = ψ  ∧  π_{g∘f}(w) = ρ
  ```

  where `f_V := pr_V ∘ f_cl : W × W' → V` is the left-factor classical residue.
  The relation is *surjective* onto `M(g ∘ f)`: for every `ρ : M(g ∘ f)`,
  surjectivity of `π_{g∘f}` yields a witness `w`, and any `w' : W'` produces a
  compatible pair `(φ, ψ) = (π_f(w), π_g(f_V(w, w')))`.

  This file is pure finite set theory: it does not depend on the vector bundle
  (`VBund`) structure, only on functions between finite types. The connection
  to `VBundHom` (instantiating `f_cl` with the classical part of a bundle
  morphism) is deferred to a later layer.

  See `PrelimHLEP.md` §"Partial Linearization" and §"Composition" for the
  mathematical background.
-/

import Mathlib

noncomputable section

namespace Formalization

/-! ## The measurement classifier and `M(f)`

For a classical map `f_cl : W × W' → V × V'`, the *measurement classifier* is
the map `κ_f : W → (W' → V')` that sends `w` to the function
`w' ↦ pr_{V'}(f_cl(w, w'))`. The measurement result set `M(f)` is the image
(range) of `κ_f`.
-/

section MeasSet

variable {W W' V V' : Type}

/-- The measurement classifier: `κ_f(w) = (w' ↦ pr_{V'}(f_cl(w, w')))`.

This is the map whose image is `M(f)`. -/
def measMap (fcl : W × W' → V × V') : W → (W' → V') :=
  fun w w' => (fcl (w, w')).2

/-- The measurement result set `M(f)`, defined as the range of `measMap`.

Elements of `M(f)` are functions `W' → V'` that arise as the right-component
classical residue of `f_cl` for some left base point `w : W`. -/
def MeasSet (fcl : W × W' → V × V') : Type :=
  Set.range (measMap fcl)

/-- The canonical surjection `π_f : W ↠ M(f)`.

Sends `w : W` to `κ_f(w)` viewed as an element of the range. -/
def MeasSet.π (fcl : W × W' → V × V') : W → MeasSet fcl :=
  fun w => ⟨measMap fcl w, Set.mem_range_self w⟩

/-- The canonical injection `ι_f : M(f) ↪ (W' → V')` (subtype inclusion). -/
def MeasSet.ι (fcl : W × W' → V × V') : MeasSet fcl → (W' → V') :=
  Subtype.val

@[simp]
theorem MeasSet.ι_apply (fcl : W × W' → V × V') (φ : MeasSet fcl) :
    MeasSet.ι fcl φ = φ.val := rfl

@[simp]
theorem MeasSet.π_val (fcl : W × W' → V × V') (w : W) :
    (MeasSet.π fcl w).val = measMap fcl w := rfl

/-- `π_f` is surjective onto `M(f)`. -/
theorem MeasSet.π_surjective (fcl : W × W' → V × V') :
    Function.Surjective (MeasSet.π fcl) := by
  intro φ
  obtain ⟨w, hw⟩ := φ.prop
  exact ⟨w, Subtype.ext hw⟩

/-- The left-factor classical residue `f_V := pr_V ∘ f_cl : W × W' → V`.

This is the `V`-component of `f_cl`, used to connect `π_f` and `π_g` in the
compatibility relation. -/
def fV (fcl : W × W' → V × V') : W × W' → V :=
  fun ww' => (fcl ww').1

/-- `M(f)` has decidable equality when the function space `W' → V'` does. -/
instance MeasSet.decidableEq (fcl : W × W' → V × V') [DecidableEq (W' → V')] :
    DecidableEq (MeasSet fcl) :=
  Subtype.instDecidableEq

end MeasSet

/-! ## The compatibility relation `~`

Given composable morphisms `f` and `g` with measurement surjections `π_f`,
`π_g`, `π_{g∘f}` and left-factor residue `f_V`, the relation `(φ, ψ) ~ ρ`
holds iff there exist classical inputs `w : W` and `w' : W'` that jointly
witness all three measurement outcomes.
-/

section MeasRel

variable {W W' V Mf Mg Mgf : Type}

/-- The compatibility relation: `(φ, ψ) ~ ρ` iff there exist `w : W` and
`w' : W'` witnessing `π_f(w) = φ`, `π_g(f_V(w, w')) = ψ`, and
`π_{g∘f}(w) = ρ`.

The surjections `π_f : W → M(f)`, `π_g : V → M(g)`, `π_{g∘f} : W → M(g∘f)`
and the residue `f_V : W × W' → V` are parameters. -/
def MeasRel (πf : W → Mf) (πg : V → Mg) (πgf : W → Mgf)
    (fV : W × W' → V) (φ : Mf) (ψ : Mg) (ρ : Mgf) : Prop :=
  ∃ w : W, ∃ w' : W',
    πf w = φ ∧ πg (fV (w, w')) = ψ ∧ πgf w = ρ

/-- A pair `(w, w')` *witnesses* `(φ, ψ) ~ ρ` iff it satisfies the three
equations. This is a convenient unpacking of the existential. -/
def MeasRel.Witness (πf : W → Mf) (πg : V → Mg) (πgf : W → Mgf)
    (fV : W × W' → V) (φ : Mf) (ψ : Mg) (ρ : Mgf) (w : W) (w' : W') : Prop :=
  πf w = φ ∧ πg (fV (w, w')) = ψ ∧ πgf w = ρ

theorem MeasRel.exists_witness {πf : W → Mf} {πg : V → Mg} {πgf : W → Mgf}
    {fV : W × W' → V} {φ : Mf} {ψ : Mg} {ρ : Mgf}
    (h : MeasRel πf πg πgf fV φ ψ ρ) :
    ∃ w : W, ∃ w' : W',
      MeasRel.Witness πf πg πgf fV φ ψ ρ w w' := h

theorem MeasRel.of_witness {πf : W → Mf} {πg : V → Mg} {πgf : W → Mgf}
    {fV : W × W' → V} {φ : Mf} {ψ : Mg} {ρ : Mgf}
    {w : W} {w' : W'}
    (h : MeasRel.Witness πf πg πgf fV φ ψ ρ w w') :
    MeasRel πf πg πgf fV φ ψ ρ :=
  ⟨w, w', h⟩

end MeasRel

/-! ## Surjectivity of `~` onto `M(g ∘ f)`

The relation `~` is surjective onto `M(g ∘ f)`: for every `ρ : M(g ∘ f)`,
surjectivity of `π_{g∘f}` yields a witness `w : W`, and any `w' : W'`
produces a compatible pair `(φ, ψ) = (π_f(w), π_g(f_V(w, w')))`.
-/

section MeasRelSurjectivity

variable {W W' V Mf Mg Mgf : Type}
  (πf : W → Mf) (πg : V → Mg) (πgf : W → Mgf) (fV : W × W' → V)

/-- The compatibility relation `~` is surjective onto `M(g ∘ f)`:

For every `ρ : M(g ∘ f)`, surjectivity of `π_{g∘f}` yields `w : W` with
`π_{g∘f}(w) = ρ`; picking any `w' : W'` and setting `φ := π_f(w)` and
`ψ := π_g(f_V(w, w'))` gives `(φ, ψ) ~ ρ`. -/
theorem MeasRel.surjective
    (hπgf : Function.Surjective πgf)
    [Nonempty W'] (ρ : Mgf) :
    ∃ φ : Mf, ∃ ψ : Mg, MeasRel πf πg πgf fV φ ψ ρ := by
  obtain ⟨w, hw⟩ := hπgf ρ
  obtain ⟨w'⟩ := ‹Nonempty W'›
  exact ⟨πf w, πg (fV (w, w')), w, w', rfl, rfl, hw⟩

/-- Explicit witness form of surjectivity: for every `ρ`, there exist
`φ`, `ψ`, `w`, `w'` such that `(φ, ψ) ~ ρ` is witnessed by `(w, w')`. -/
theorem MeasRel.surjective_witness
    (hπgf : Function.Surjective πgf)
    [Nonempty W'] (ρ : Mgf) :
    ∃ φ : Mf, ∃ ψ : Mg, ∃ w : W, ∃ w' : W',
      MeasRel.Witness πf πg πgf fV φ ψ ρ w w' := by
  obtain ⟨w, hw⟩ := hπgf ρ
  obtain ⟨w'⟩ := ‹Nonempty W'›
  exact ⟨πf w, πg (fV (w, w')), w, w', rfl, rfl, hw⟩

end MeasRelSurjectivity

/-! ## Concrete instantiation with `MeasSet`

When the surjections `π_f`, `π_g`, `π_{g∘f}` are the canonical surjections
from `MeasSet`, the relation `~` specializes to the concrete compatibility
relation used in the composition theorem.
-/

section MeasRelConcrete

variable {W W' V V' X X' : Type}

/-- The left-factor residue for a morphism `f` with classical part
`f_cl : W × W' → V × V'`. -/
abbrev measFV (fcl : W × W' → V × V') : W × W' → V :=
  Formalization.fV fcl

/-- The concrete compatibility relation for composable morphisms `f` and `g`
with classical parts `f_cl : W × W' → V × V'` and `g_cl : V × V' → X × X'`,
and composite classical part `gf_cl : W × W' → X × X'`.

Here `π_f`, `π_g`, `π_{g∘f}` are the canonical `MeasSet.π` surjections. -/
def MeasRel.concrete
    (fcl : W × W' → V × V') (gcl : V × V' → X × X')
    (gfcl : W × W' → X × X')
    (φ : MeasSet fcl) (ψ : MeasSet gcl) (ρ : MeasSet gfcl) : Prop :=
  MeasRel (MeasSet.π fcl) (MeasSet.π gcl) (MeasSet.π gfcl) (fV fcl) φ ψ ρ

/-- The concrete relation `~` is surjective onto `M(g ∘ f)` when `W'` is
nonempty. -/
theorem MeasRel.concrete_surjective
    (fcl : W × W' → V × V') (gcl : V × V' → X × X')
    (gfcl : W × W' → X × X')
    [Nonempty W'] (ρ : MeasSet gfcl) :
    ∃ φ : MeasSet fcl, ∃ ψ : MeasSet gcl,
      MeasRel.concrete fcl gcl gfcl φ ψ ρ :=
  MeasRel.surjective (MeasSet.π fcl) (MeasSet.π gcl) (MeasSet.π gfcl)
    (fV fcl) (MeasSet.π_surjective gfcl) ρ

end MeasRelConcrete

/-! ## Classical part of the Composition Theorem

The Composition Theorem relates the linearized morphisms
`Lin g_ψ ∘ Lin f_φ` and `Lin (g ∘ f)_ρ` on basis vectors compatible with the
measurement results. Its **classical part** is pure finite set theory:

Given composable morphisms `f` and `g` with classical parts `f_cl` and
`g_cl` satisfying the composition law `(g ∘ f)_cl = g_cl ∘ f_cl`, and a
witness `(w, w')` of `(φ, ψ) ~ ρ`, the classical-part identity

$$
  \iota_g(\psi) \circ \iota_f(\phi) \;=\; \iota_{g\circ f}(\rho)
  \quad : \quad W' \to X'
$$

holds, where `ι` denotes the subtype inclusion of `M(·)` into the function
space. This is the base-space component of the Composition Theorem; the
fiber component (requiring linear algebra) is deferred to a later layer.
-/

section CompositionClassical

variable {W W' V V' X X' : Type}

/-- The classical composition law: `(g ∘ f)_cl = g_cl ∘ f_cl`.

This is the key hypothesis relating the composite's classical part to the
parts of `f` and `g`. -/
def ClassicalComp (fcl : W × W' → V × V')
    (gcl : V × V' → X × X') (gfcl : W × W' → X × X') : Prop :=
  gfcl = gcl ∘ fcl

/-- The classical-part identity of the Composition Theorem.

Given the composition law `gfcl = gcl ∘ fcl` and a witness `(w, w')` of
`(φ, ψ) ~ ρ` (via the canonical `MeasSet.π` surjections), the classical-part
identity holds *at the witness point* `w'`:

$$
  \iota_g(\psi)\bigl(\iota_f(\phi)(w')\bigr) \;=\; \iota_{g\circ f}(\rho)(w').
$$

Both sides equal `pr_{X'}((g ∘ f)_cl(w, w'))`. This is the base-space
component of the Composition Theorem at a single witness; the fiber
component (requiring linear algebra) is deferred to a later layer. -/
theorem composition_classical
    (fcl : W × W' → V × V') (gcl : V × V' → X × X')
    (gfcl : W × W' → X × X')
    (hcomp : ClassicalComp fcl gcl gfcl)
    (φ : MeasSet fcl) (ψ : MeasSet gcl) (ρ : MeasSet gfcl)
    (w : W) (w' : W')
    (h1 : MeasSet.π fcl w = φ)
    (h2 : MeasSet.π gcl (fV fcl (w, w')) = ψ)
    (h3 : MeasSet.π gfcl w = ρ) :
    MeasSet.ι gcl ψ (MeasSet.ι fcl φ w') = MeasSet.ι gfcl ρ w' := by
  -- Unfold the composition law: gfcl = gcl ∘ fcl.
  subst hcomp
  -- From the witnessing equations, extract the underlying function equalities.
  -- h1 : π_f w = φ  ⟹  φ.val = measMap fcl w
  have hφ : φ.val = measMap fcl w := by
    rw [← h1]; exact (MeasSet.π_val fcl w).symm
  -- h2 : π_g (fV fcl (w, w')) = ψ  ⟹  ψ.val = measMap gcl (fV fcl (w, w'))
  have hψ : ψ.val = measMap gcl (fV fcl (w, w')) := by
    rw [← h2]; exact (MeasSet.π_val gcl (fV fcl (w, w'))).symm
  -- h3 : π_{g∘f} w = ρ  ⟹  ρ.val = measMap (gcl ∘ fcl) w
  have hρ : ρ.val = measMap (gcl ∘ fcl) w := by
    rw [← h3]; exact (MeasSet.π_val (gcl ∘ fcl) w).symm
  -- Unfold ι (subtype val) and substitute.
  show ψ.val (φ.val w') = ρ.val w'
  rw [hφ, hψ, hρ]
  -- Now: (gcl ((fcl (w, w')).1, (fcl (w, w')).2)).2 = ((gcl ∘ fcl) (w, w')).2
  -- The key: (fcl (w, w')).1 = fV fcl (w, w') by definition of fV,
  -- so (fcl (w, w')) = (fV fcl (w, w'), (fcl (w, w')).2), and
  -- gcl (fV fcl (w, w'), (fcl (w, w')).2) = gcl (fcl (w, w')).
  dsimp only [measMap, fV, Function.comp]

end CompositionClassical

end Formalization
