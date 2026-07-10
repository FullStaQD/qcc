/-
  # Morphisms of Vector Bundles

  A morphism of `VBund`s consists of
  * a classical part `cl : W → W'` on the base, and
  * a `W`-indexed family of linear maps `lin,w : H_w →ₗ H'_{cl w}` on fibers.

  This is the denotation of a (pure) function in the PrelimHLEP dialect.
-/

import Mathlib
import Formalization.VBund.Basic

noncomputable section

open scoped TensorProduct

namespace Formalization

/-- A morphism of vector bundles: a classical base map together with a
fiberwise linear map. The codomain fiber is indexed by `cl w`, so the
linear-map family is dependent on the classical part.

The algebraic structure on the fibers is supplied as implicit instance
parameters to the structure, so that `LinearMap` can be formed. -/
structure VBundHom (E E' : VBund)
    [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)] where
  /-- The classical part: a function on the base spaces. -/
  cl : E.base → E'.base
  /-- The linear part: a fiberwise linear map. The codomain fiber is indexed
  by `cl w`, so the family is dependent on the classical part. -/
  lin : ∀ w, E.fiber w →ₗ[ℂ] E'.fiber (cl w)

/-- Identity morphism. -/
@[simp]
def VBundHom.id (E : VBund)
    [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, FiniteDimensional ℂ (E.fiber w)] : VBundHom E E where
  cl := fun w => w
  lin := fun _ => LinearMap.id

/-- Composition of morphisms. -/
@[simp]
def VBundHom.comp {E E' E'' : VBund}
    [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
    [∀ w, AddCommGroup (E''.fiber w)] [∀ w, Module ℂ (E''.fiber w)]
    (g : VBundHom E' E'') (f : VBundHom E E') : VBundHom E E'' where
  cl := fun w => g.cl (f.cl w)
  lin := fun w => (g.lin (f.cl w)).comp (f.lin w)

/-- The classical part of a composite is the composite of the classical
parts. -/
@[simp]
theorem VBundHom.comp_cl {E E' E'' : VBund}
    [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
    [∀ w, AddCommGroup (E''.fiber w)] [∀ w, Module ℂ (E''.fiber w)]
    (g : VBundHom E' E'') (f : VBundHom E E') :
    (g.comp f).cl = g.cl ∘ f.cl := rfl

/-- The linear part of a composite is the composite of the linear parts,
with the base index tracked through the classical part of the first map. -/
@[simp]
theorem VBundHom.comp_lin {E E' E'' : VBund}
    [∀ w, AddCommGroup (E.fiber w)] [∀ w, Module ℂ (E.fiber w)]
    [∀ w, AddCommGroup (E'.fiber w)] [∀ w, Module ℂ (E'.fiber w)]
    [∀ w, AddCommGroup (E''.fiber w)] [∀ w, Module ℂ (E''.fiber w)]
    (g : VBundHom E' E'') (f : VBundHom E E') (w : E.base) :
    (g.comp f).lin w = (g.lin (f.cl w)).comp (f.lin w) := rfl

end Formalization
