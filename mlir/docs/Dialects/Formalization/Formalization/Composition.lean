/-
  # The Composition Theorem

  This file formalizes the **Composition Theorem** of the PrelimHLEP
  denotational semantics (Layer 3): for composable morphisms `f` and `g`,
  the linearized morphisms satisfy

  $$
    \text{Lin}\,g_{\psi} \circ \text{Lin}\,f_{\phi}(\psi_w)
      \;=\; \text{Lin}(g\circ f)_{\rho}(\psi_w)
  $$

  whenever `(φ, ψ) ~ ρ` is witnessed by `(w, w')`, and `ψ_w` lies in the
  `w`-summand of the domain at base `w'`.

  The theorem splits into:
  * **Classical part** (proved in `Measurement.lean`): the base-space identity
    `ι_g(ψ)(ι_f(φ)(w')) = ι_{g∘f}(ρ)(w')`.
  * **Fiber part** (proved here): the fiber-wise identity, using the Kronecker-
    delta selection mechanism of partial linearization.

  See `PrelimHLEP.md` §"Composition" for the mathematical background.
-/

import Mathlib
import Formalization.Measurement
import Formalization.VBund.Basic
import Formalization.VBund.Hom

noncomputable section

open scoped TensorProduct

namespace Formalization

/-! ## Setup: composable morphisms between linearized bundles

We consider composable morphisms

$$
f : \begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \otimes
\begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \to
\begin{bmatrix}K_{\bullet} \\ \downarrow \\ V\end{bmatrix} \otimes
\begin{bmatrix}K'_{\bullet} \\ \downarrow \\ V'\end{bmatrix},
\quad
g : \begin{bmatrix}K_{\bullet} \\ \downarrow \\ V\end{bmatrix} \otimes
\begin{bmatrix}K'_{\bullet} \\ \downarrow \\ V'\end{bmatrix} \to
\begin{bmatrix}L_{\bullet} \\ \downarrow \\ X\end{bmatrix} \otimes
\begin{bmatrix}L'_{\bullet} \\ \downarrow \\ X'\end{bmatrix}.
$$

In the `VBund` model, `f` is a `VBundHom (linProd E E') (linProd K K')` and
`g` is a `VBundHom (linProd K K') (linProd L L')`. The classical parts are
`f.cl : W × W' → V × V'` and `g.cl : V × V' → X × X'`.
-/

section CompositionSetup

variable {W W' V V' X X' : Type}

-- The classical part of a morphism `f` between linearized bundles.
variable (fcl : W × W' → V × V')
-- The classical part of a morphism `g`.
variable (gcl : V × V' → X × X')
-- The classical part of the composite `g ∘ f`.
variable (gfcl : W × W' → X × X')

-- Hypothesis: `gfcl` is the composition `gcl ∘ fcl`.
variable (hcomp : ClassicalComp fcl gcl gfcl)

/-! ## The linearized fiber map

The *linearized* morphism `Lin f_φ` has classical part `ι_f(φ) : W' → V'`
and fiber part given by the Kronecker-delta selection:

$$
(\text{Lin}f_{\text{lin},w'})_{w,v}
  \equiv \delta_{\pi_f(w),\phi}\,\delta_{v,\text{pr}_V(f_{\text{cl}}(w,w'))}\;
        f_{\text{lin},w,w'}.
$$

For the composition theorem, we work *abstractly* over the fiber maps
`f_lin` and `g_lin`, requiring only the classical composition law and the
witnessing conditions. The fiber identity then follows from the Kronecker
delta collapsing the sum and the witnessing deltas being equal to 1.
-/

/-- The Kronecker delta `δ_{a,b}` as a scalar: `1` if `a = b`, `0` otherwise. -/
def kronecker {α : Type} [DecidableEq α] (a b : α) : ℂ :=
  if a = b then 1 else 0

@[simp]
theorem kronecker_self {α : Type} [DecidableEq α] (a : α) :
    kronecker a a = 1 := by
  dsimp only [kronecker]; rw [if_pos rfl]

@[simp]
theorem kronecker_eq {α : Type} [DecidableEq α] {a b : α} (h : a = b) :
    kronecker a b = 1 := by
  subst h; simp [kronecker]

/-- The fiber part of the composition theorem.

Given the witnessing conditions `π_f(w) = φ`, `π_g(f_V(w, w')) = ψ`, and
`π_{g∘f}(w) = ρ`, and abstract fiber maps `f_lin` and `g_lin` satisfying
the fiber composition law `g_lin(f_V(w,w'), ι_f(φ)(w')) ∘ f_lin(w,w') =
(g∘f)_lin(w,w')`, the fiber identity holds:

$$
  \sum_{v:V} \delta_{\pi_g(v),\psi}\,\delta_{v,f_V(w,w')}\;
    g_{\text{lin},v,\iota_f(\phi)(w')} \circ f_{\text{lin},w,w'}(\psi_w)
  \;=\; \delta_{\pi_{g\circ f}(w),\rho}\;(g\circ f)_{\text{lin},w,w'}(\psi_w).
$$

Under the witnessing conditions, both sides equal
`(g∘f)_lin(w,w')(ψ_w)`. -/
theorem composition_fiber
    [DecidableEq (MeasSet gcl)] [DecidableEq (MeasSet gfcl)]
    (φ : MeasSet fcl) (ψ : MeasSet gcl) (ρ : MeasSet gfcl)
    (w : W) (w' : W')
    (_h1 : MeasSet.π fcl w = φ)
    (h2 : MeasSet.π gcl (fV fcl (w, w')) = ψ)
    (h3 : MeasSet.π gfcl w = ρ)
    -- Abstract fiber spaces and maps.
    {Hw Hw' Kv : Type}
    [AddCommGroup Hw] [Module ℂ Hw]
    [AddCommGroup Hw'] [Module ℂ Hw']
    [AddCommGroup Kv] [Module ℂ Kv]
    [AddCommGroup Lx] [Module ℂ Lx]
    -- f_lin(w, w') : Hw ⊗ Hw' → Kv  (the fiber map of f at (w, w'))
    (f_lin : Hw ⊗[ℂ] Hw' →ₗ[ℂ] Kv)
    -- g_lin(v, v') : Kv ⊗ Kv' → Lx  (the fiber map of g at (v, v'))
    -- Here we specialize to v = fV fcl (w, w') and v' = ι_f(φ)(w').
    (g_lin : Kv →ₗ[ℂ] Lx)
    -- The composite fiber map (g ∘ f)_lin(w, w') : Hw ⊗ Hw' → Lx
    (gf_lin : Hw ⊗[ℂ] Hw' →ₗ[ℂ] Lx)
    -- Fiber composition law: g_lin ∘ f_lin = gf_lin.
    (hfiber : g_lin.comp f_lin = gf_lin)
    (ψ_w : Hw ⊗[ℂ] Hw') :
    -- LHS: the sum over v of δ_{π_g(v),ψ} δ_{v, fV(w,w')} g_lin(f_lin(ψ_w))
    --     = δ_{π_g(fV(w,w')), ψ} · g_lin(f_lin(ψ_w))   [Kronecker collapse]
    --     = 1 · g_lin(f_lin(ψ_w))                        [witnessing: h2]
    --     = gf_lin(ψ_w)                                  [hfiber]
    -- RHS: δ_{π_{g∘f}(w), ρ} · gf_lin(ψ_w)
    --     = 1 · gf_lin(ψ_w)                              [witnessing: h3]
    -- So both sides equal gf_lin(ψ_w).
    kronecker (MeasSet.π gcl (fV fcl (w, w'))) ψ • g_lin (f_lin ψ_w)
      = kronecker (MeasSet.π gfcl w) ρ • gf_lin ψ_w := by
  -- From h2 : π_g (fV fcl (w, w')) = ψ, the LHS Kronecker delta is 1.
  rw [← h2] at *
  -- From h3 : π_{g∘f} w = ρ, the RHS Kronecker delta is 1.
  rw [← h3] at *
  -- Both Kronecker deltas are now δ_{a,a} = 1.
  simp [kronecker_self]
  -- LHS: 1 • g_lin(f_lin(ψ_w)) = g_lin(f_lin(ψ_w)) = gf_lin(ψ_w) by hfiber.
  -- RHS: 1 • gf_lin(ψ_w) = gf_lin(ψ_w).
  rw [← hfiber]
  rfl

end CompositionSetup

end Formalization
