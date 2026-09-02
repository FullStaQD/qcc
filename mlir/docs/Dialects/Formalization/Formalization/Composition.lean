/-
  # The Composition Theorem

  This file formalizes the **Composition Theorem** of the PrelimHLEP
  denotational semantics (Layer 3): for composable morphisms `f` and `g`,
  the *partially linearized* morphisms satisfy

  $$
    \text{Lin}\,g_{\psi} \circ \text{Lin}\,f_{\phi}(\psi_w)
      \;=\; \text{Lin}(g\circ f)_{\rho}(\psi_w)
  $$

  whenever `(φ, ψ) ~ ρ` is witnessed by `(w, w')`, and `ψ_w` lies in the
  `w`-summand of the domain at base `w'`.

  Partial linearization appears here as a **concrete** construction on genuine
  bundle morphisms, with *no simplifying assumptions on the fibers*:

  * `TensorHom E E' F F'` is a bundle morphism `E ⊗ E' → F ⊗ F'` equipped with
    the tensor decomposition of its domain and codomain — the data partial
    linearization consumes. Partial linearization always acts on the *left*
    factors `E`, `F`.
  * `TensorHom.linearize` turns such a morphism, together with a measurement
    result `φ : M(f)`, into an honest `VBundHom` between the linearized bundles
    `Lin[E] ⊗ E' → Lin[F] ⊗ F'`.
  * `composition` states the theorem directly in terms of `VBundHom.comp`,
    comparing `(g.linearize ψ).comp (f.linearize φ)` with
    `(g.comp f).linearize ρ`.

  Because the codomain bundle has genuinely base-dependent fibers, the two sides
  live over *propositionally* equal base points, and the fiber comparison is
  made along the base identity `composition_classical` via `▸` (the same
  transport phenomenon that already appears in `VBundHom.ext`). No fiber is
  assumed constant.

  See `PrelimHLEP.md` §"Composition" for the mathematical background.
-/

import Mathlib
import Formalization.Measurement
import Formalization.VBund.Basic
import Formalization.VBund.Hom
import Formalization.VBund.Constructors

noncomputable section

open scoped TensorProduct

namespace Formalization

/-! ## Transport along equal base points

The codomain of a linearized morphism is a bundle with base-dependent fibers.
Comparing values over *propositionally* equal base points requires a transport,
packaged here as a linear map. -/

/-- Transport an element along an equality of base points in a fiber family,
as a linear map `β i →ₗ β j` from `h : i = j`. -/
def fiberTransport {ι : Type} {β : ι → Type}
    [∀ i, AddCommGroup (β i)] [∀ i, Module ℂ (β i)] {i j : ι} (h : i = j) :
    β i →ₗ[ℂ] β j :=
  Eq.rec (motive := fun k _ => β i →ₗ[ℂ] β k) LinearMap.id h

@[simp]
theorem fiberTransport_self {ι : Type} {β : ι → Type}
    [∀ i, AddCommGroup (β i)] [∀ i, Module ℂ (β i)] {i : ι} (h : i = i) :
    fiberTransport (β := β) h = LinearMap.id := by
  rw [Subsingleton.elim h rfl]; rfl

/-! ## Fiber instances for the linearized bundle

`VBundHom` requires the fibers of its (co)domain to carry module structure as
`∀`-instances. For `lin E` the fiber is the constant direct sum `⊕_w E.fiber w`,
whose instances come from Mathlib. Registering them here lets `VBundHom` over
`linProd (lin E) E'` be formed. -/

section LinInstances

variable (E : VBund) [Fintype E.base] [DecidableEq E.base]
  [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]

instance : ∀ u, AddCommGroup ((lin E).fiber u) :=
  fun _ => inferInstanceAs (AddCommGroup (Π₀ w, E.fiber w))

instance : ∀ u, Module ℂ ((lin E).fiber u) :=
  fun _ => inferInstanceAs (Module ℂ (Π₀ w, E.fiber w))

end LinInstances

/-! ## Tensor-decomposed morphisms

The auxiliary data structure on which partial linearization acts: a bundle
morphism together with the chosen tensor decomposition of its domain
(`E ⊗ E'`) and codomain (`F ⊗ F'`). Concretely it stores the classical part
`cl : W × W' → V × V'` and the fiberwise linear maps
`lin_{w,w'} : H_w ⊗ H'_{w'} → K_v ⊗ K'_{v'}` with `(v, v') = cl(w, w')`. -/

structure TensorHom (E E' F F' : VBund)
    [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
    [∀ v, AddCommGroup (F.fiber v)] [∀ v, Module ℂ (F.fiber v)]
    [∀ v, AddCommGroup (F'.fiber v)] [∀ v, Module ℂ (F'.fiber v)] where
  /-- The classical part `f_cl : W × W' → V × V'`. -/
  cl : E.base × E'.base → F.base × F'.base
  /-- The fiber map `f_{lin, w, w'} : H_w ⊗ H'_{w'} → K_v ⊗ K'_{v'}`, where
  `(v, v') = cl(w, w')`. Named `flin` to avoid clashing with the linearization
  functor `lin`. -/
  flin : ∀ (w : E.base) (w' : E'.base),
    (E.fiber w ⊗[ℂ] E'.fiber w') →ₗ[ℂ]
      (F.fiber (cl (w, w')).1 ⊗[ℂ] F'.fiber (cl (w, w')).2)

section TensorHomOps

variable {E E' F F' G G' : VBund}
  [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
  [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
  [∀ v, AddCommGroup (F.fiber v)] [∀ v, Module ℂ (F.fiber v)]
  [∀ v, AddCommGroup (F'.fiber v)] [∀ v, Module ℂ (F'.fiber v)]
  [∀ x, AddCommGroup (G.fiber x)] [∀ x, Module ℂ (G.fiber x)]
  [∀ x, AddCommGroup (G'.fiber x)] [∀ x, Module ℂ (G'.fiber x)]

/-- Composition of tensor-decomposed morphisms. The classical parts compose and
the fiber maps compose through the classical residue of `f`, so that
`(g ∘ f)_{lin,w,w'} = g_{lin, f_V(w,w'), ·} ∘ f_{lin,w,w'}` holds by
construction. -/
def TensorHom.comp (g : TensorHom F F' G G') (f : TensorHom E E' F F') :
    TensorHom E E' G G' where
  cl := g.cl ∘ f.cl
  flin := fun w w' => (g.flin (f.cl (w, w')).1 (f.cl (w, w')).2).comp (f.flin w w')

end TensorHomOps

/-! ## Partial linearization -/

section PartialLinearization

variable {E E' F F' : VBund}
  [Fintype E.base] [DecidableEq E.base] [Fintype F.base] [DecidableEq F.base]
  [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
  [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
  [∀ v, AddCommGroup (F.fiber v)] [∀ v, Module ℂ (F.fiber v)]
  [∀ v, AddCommGroup (F'.fiber v)] [∀ v, Module ℂ (F'.fiber v)]

/-- The codomain base point identity: if `π_f(w) = φ`, then the classical
residue `pr_{V'}(f_cl(w, w'))` equals `ι_f(φ)(w')`, the base image of `Lin f`.
This is what justifies transporting `f`'s right-factor output into the fiber of
the linearized codomain. -/
theorem meas_hcod {W W' V V' : Type} (cl : W × W' → V × V') (φ : MeasSet cl)
    {w : W} {w' : W'} (h : MeasSet.π cl w = φ) :
    (cl (w, w')).2 = MeasSet.ι cl φ w' := by
  rw [← h]; rfl

/-- **Partial linearization** of a tensor-decomposed morphism `t`, at a
measurement result `φ : M(t)`, as a genuine `VBundHom` between the linearized
bundles `Lin[E] ⊗ E' → Lin[F] ⊗ F'`.

* Classical part: `ι_t(φ) : W' → V'` (on the singleton-collapsed left base).
* Fiber part over `w'`: the Kronecker-delta selection
  `⊕_w [π_t(w) = φ] · (lsingle_{pr_V(t_cl(w,w'))} ⊗ transport) ∘ t_lin,w,w'`,
  where `DFinsupp.lsingle` places the image in the `pr_V(t_cl(w,w'))`-summand
  (the delta `δ_{v,·}`), the `if`-guard is the delta `δ_{π_t(w),φ}`, and the
  `fiberTransport` moves `t`'s right-factor output `K'_{pr_{V'}(t_cl(w,w'))}`
  into `K'_{ι_t(φ)(w')}` (equal by `meas_hcod`). -/
def TensorHom.linearize (t : TensorHom E E' F F') [DecidableEq (MeasSet t.cl)]
    (φ : MeasSet t.cl) :
    VBundHom (linProd (lin E) E') (linProd (lin F) F') where
  cl := fun b => ((), MeasSet.ι t.cl φ b.2)
  lin := fun b =>
    TensorProduct.lift <| DFinsupp.lsum ℂ fun w =>
      TensorProduct.curry <|
        if h : MeasSet.π t.cl w = φ then
          (TensorProduct.map (DFinsupp.lsingle (t.cl (w, b.2)).1)
            (fiberTransport (meas_hcod t.cl φ h))).comp (t.flin w b.2)
        else 0

omit [Fintype E.base] [Fintype F.base] in
/-- Applying `t.linearize (π_t w)` to a single summand `single w hw ⊗ h'`
(written with the summand injection `map (lsingle w) id`). The sum collapses to
the single term selected by `w`.

The measurement result is fixed to the *witness* `π_t(w)`; this makes the
codomain base point `ι_t(π_t w)(w')` definitionally the classical residue
`pr_{V'}(t_cl(w, w'))`, so the transport is the identity and does not appear. -/
theorem TensorHom.linearize_apply_summand (t : TensorHom E E' F F')
    [DecidableEq (MeasSet t.cl)] (w : E.base) (w' : E'.base)
    (x : E.fiber w ⊗[ℂ] E'.fiber w') :
    (t.linearize (MeasSet.π t.cl w)).lin ((), w')
        (TensorProduct.map (DFinsupp.lsingle w) LinearMap.id x)
      = TensorProduct.map (DFinsupp.lsingle (t.cl (w, w')).1) LinearMap.id
          (t.flin w w' x) := by
  -- The fiber map is `lift (lsum F)`; precomposing with the `w`-summand
  -- injection isolates the `w`-th component.
  have key : (TensorProduct.lift (DFinsupp.lsum ℂ fun w0 =>
        TensorProduct.curry
          (if h : MeasSet.π t.cl w0 = MeasSet.π t.cl w then
            (TensorProduct.map (DFinsupp.lsingle (t.cl (w0, w')).1)
              (fiberTransport (meas_hcod t.cl _ h))).comp (t.flin w0 w')
          else 0))).comp
        (TensorProduct.map (DFinsupp.lsingle w) LinearMap.id)
      = (if h : MeasSet.π t.cl w = MeasSet.π t.cl w then
            (TensorProduct.map (DFinsupp.lsingle (t.cl (w, w')).1)
              (fiberTransport (meas_hcod t.cl _ h))).comp (t.flin w w')
          else 0) := by
    apply TensorProduct.ext'
    intro a b
    simp only [LinearMap.comp_apply, TensorProduct.map_tmul, LinearMap.id_coe,
      id_eq, DFinsupp.lsingle_apply, TensorProduct.lift.tmul, DFinsupp.lsum_single,
      TensorProduct.curry_apply]
  have happ := LinearMap.congr_fun key x
  rw [dif_pos rfl, LinearMap.comp_apply, LinearMap.comp_apply] at happ
  -- `fiberTransport (meas_hcod … rfl)` is a self-transport, definitionally the
  -- identity; `exact` closes it up to that defeq.
  exact happ

end PartialLinearization

/-! ## The Composition Theorem -/

section CompositionTheorem

variable {E E' F F' G G' : VBund}
  [Fintype E.base] [DecidableEq E.base]
  [Fintype F.base] [DecidableEq F.base]
  [Fintype G.base] [DecidableEq G.base]
  [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
  [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
  [∀ v, AddCommGroup (F.fiber v)] [∀ v, Module ℂ (F.fiber v)]
  [∀ v, AddCommGroup (F'.fiber v)] [∀ v, Module ℂ (F'.fiber v)]
  [∀ x, AddCommGroup (G.fiber x)] [∀ x, Module ℂ (G.fiber x)]
  [∀ x, AddCommGroup (G'.fiber x)] [∀ x, Module ℂ (G'.fiber x)]

omit [Fintype E.base] [Fintype F.base] [Fintype G.base] in
/-- **The Composition Theorem**, stated in terms of the concrete partial
linearization `TensorHom.linearize` and `VBundHom.comp`.

Let `f`, `g` be composable tensor-decomposed morphisms and let `(φ, ψ) ~ ρ` be
witnessed by `(w, w')`:

* `h1 : π_f(w) = φ`,
* `h2 : π_g(f_V(w, w')) = ψ`   (where `f_V(w, w') = pr_V(f_cl(w, w'))`),
* `h3 : π_{g∘f}(w) = ρ`.

Then the composite of the linearized morphisms `(g.linearize ψ).comp
(f.linearize φ)` agrees with the joint linearization `(g.comp f).linearize ρ`
on the `w`-summand `map (lsingle w) id x` of the domain fiber at base `w'`.

Both morphisms land over the base points `ι_g(ψ)(ι_f(φ)(w'))` and
`ι_{g∘f}(ρ)(w')` respectively; these are equal by `composition_classical`, and
the fiber values are compared by transporting along that identity (the `▸`). -/
theorem composition
    (f : TensorHom E E' F F') (g : TensorHom F F' G G')
    [DecidableEq (MeasSet f.cl)] [DecidableEq (MeasSet g.cl)]
    [DecidableEq (MeasSet (g.comp f).cl)]
    (φ : MeasSet f.cl) (ψ : MeasSet g.cl) (ρ : MeasSet (g.comp f).cl)
    (w : E.base) (w' : E'.base)
    (h1 : MeasSet.π f.cl w = φ)
    (h2 : MeasSet.π g.cl (f.cl (w, w')).1 = ψ)
    (h3 : MeasSet.π (g.comp f).cl w = ρ)
    (x : E.fiber w ⊗[ℂ] E'.fiber w') :
    -- Base component: the two morphisms send `((), w')` to the same base point.
    ((g.linearize ψ).comp (f.linearize φ)).cl ((), w')
        = ((g.comp f).linearize ρ).cl ((), w')
    ∧
    -- Fiber component: they agree on the `w`-summand at base `w'`. The values
    -- live over the (propositionally equal) base points above, so the
    -- comparison is heterogeneous, exactly as in `VBundHom.ext`.
    HEq
      (((g.linearize ψ).comp (f.linearize φ)).lin ((), w')
        (TensorProduct.map (DFinsupp.lsingle w) LinearMap.id x))
      (((g.comp f).linearize ρ).lin ((), w')
        (TensorProduct.map (DFinsupp.lsingle w) LinearMap.id x)) := by
  -- Substituting each measurement result by its witnessing expression makes all
  -- the base-point identities (`meas_hcod`) reflexive, so every transport
  -- collapses to the identity and both base points become definitionally equal.
  subst h1; subst h2; subst h3
  refine ⟨rfl, ?_⟩
  apply heq_of_eq
  -- Unfold the outer `VBundHom.comp` definitionally; the base point at which
  -- `g` is linearized is `ι_f(φ)(w') = pr_{V'}(f_cl(w, w'))`.
  show (g.linearize (MeasSet.π g.cl (f.cl (w, w')).1)).lin ((), (f.cl (w, w')).2)
        ((f.linearize (MeasSet.π f.cl w)).lin ((), w')
          (TensorProduct.map (DFinsupp.lsingle w) LinearMap.id x))
      = ((g.comp f).linearize (MeasSet.π (g.comp f).cl w)).lin ((), w')
          (TensorProduct.map (DFinsupp.lsingle w) LinearMap.id x)
  -- `Lin f` on the `w`-summand (no transport, by the fixed-witness lemma).
  rw [TensorHom.linearize_apply_summand f w w' x]
  -- `Lin g` on the resulting `pr_V(f_cl(w,w'))`-summand.
  rw [TensorHom.linearize_apply_summand g (f.cl (w, w')).1 (f.cl (w, w')).2
        (f.flin w w' x)]
  -- The joint linearization on the `w`-summand.
  rw [TensorHom.linearize_apply_summand (g.comp f) w w' x]
  rfl

end CompositionTheorem

end Formalization
