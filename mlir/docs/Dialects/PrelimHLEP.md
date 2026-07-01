We would like to incorporate as an entry point to the compilation pipeline an IR specification which is

- high-level,
- hybrid, and
- broad.

This IR specification may correspond to one or more MLIR dialects. In this document, we refer to “the high-level dialect” as this IR specification, while keeping the question open whether it will actually be implemented as a dialect.

# Requirements

## High Level

### Abstractions

The hybrid type category most likely has three relevant operations to construct types:

- Coproduct (sum)
- Cartesian product (classical product, quantum direct sum)
- Linear product (classical product, quantum tensor product)

From these building blocks, one should be able to construct new types that only exist at compile time and cause no runtime overhead.

In addition, one can consider generics (possibly in the form of dependent types), interfaces (abstract base classes, traits, something like this), or other abstractions.

Ideally, abstractions should be zero-cost.

### Rigorous type system capturing quantum logic

On lower level quantum programming, there is a tradeoff related to the distinction between pointer and value semantics:

- Instructions at the lowest level are purely imperative. It is impossible to write an incorrect program in an assembly language, but the flow of (quantum) information is highly obscured.
- In a value-semantic IR, the flow of information is more tractable. However, in order to implement such an IR, it is important to base it on a well-defined logic. Otherwise, one has invalid programs. This is especially true for the flow of quantum information, where linear logic poses additional constraints on variables.

We want to faithfully capture the flow of hybrid quantum-classical information. To certify that a program is even physical, the language it is written in needs to be based in a hybrid type theory.

A rich type theory will allow higher order concepts, such as dependent types, (hybrid) function types, or even identity types, the latter allowing for certification of the correctness of programs.

Embedding a linear aspect into a type theory requires some form of bookkeeping, in the form of lifetimes, color palettes, or by another scheme.

## Hybrid

### Structured classical control flow

Interaction with classical parts of the program should be seamless and ideally use existing technology (e.g. `cf`, `scf`, `affine` dialects).

### Structured quantum control flow

Controlled gates have a clear meaning in terms of control flow. This has two implications:

- Rather than introducing controlled gates, the dialect should have structured “quantum if” operations that are common across high-level quantum languages.
- The knowledge about the control-flow interpretation should be encoded in the dialect. This refines the picture of the flow of hybrid information and allows for better optimizations. This is already implemented in:
  - Nvidia’s `quake` dialect, where control-wires are typed differently from regular wires, and
  - the `unqomp` algorithm for automated uncomputation.
    In both cases, the control-wires are multi-edges and break linearity, exploiting the z-commutativity property of controlled gates on the control qubits.

### (Linearization of classical types)

One possibility for introducing quantum types is to provide a quantization generic, which transforms a classical type into the quantum type that has the classical value set as a distinguished basis.

This avoids the careful introduction of quantum base types and opens the door to a monadic programming paradigm, as well as just-a-phase-style gate definitions.

Keeping the underlying classical types explicit, one could also define quantizations of classical functions, which result in free quantum functions that play an important role in silq (called “qfree” there).

## Broad

### Existing and proposed high-level languages can be embedded

MLIR’s full potential is best leveraged if as much of the lowering as possible happens within the framework. Ideally, the passing from a high-level language to the MLIR entry dialect is only a syntactic translation, not a semantic lowering or other transformation.

To meet this goal with multiple frontends, expecting newly developed ones in the future, the high-level dialect must be able to faithfully capture the language concepts of all supported input languages. It is of course hard to predict how a possible future frontend language will look like. However, the following observation helps.

Currently, the space of quantum programming languages is divided into

- low- and mid-level ad-hoc languages that are actually used and have a strong reference implementation,

- high-level languages based on solid theoretical foundations that are academic research objects and are either not implemented or ignored by the practitioner community.

Qrisp sits somewhere between these groups and can be seen as a step towards higher-level languages actually being realized.

If we are able to capture qrisp alongside the essential concepts of the most promising high-level languages in the dialect, the chance is high that it will support a well-designed future frontend language. In particular, we should consider:

- From qrisp:
  - Quantum versions of:
    - `Float`, misnomer, really fixed-point rationals.
    - `Bool`
    - `Modulus`, e.g. `Float mod 2pi`.
    - `Char`
    - `String`
  - Quantum arithmetic
    - Allow for the specification of, say, particular adder circuits.
  - Kernel decorator for automatic uncomputation.
  - Structured classical control flow.
- From quipper:
  - Value semantics
  - Functional paradigm
  - Circuit types
  - (somewhat) quantization-based types
- From qurts:
  - …
- From silq:
  - …
- From …

### Syntactic sugaring for common concepts

- Automatic uncomputation is a common feature of high-level programming languages. If it is implicit, linearity will be broken on the highest level.
- Just-a-phase style if-let statements are a neat way to define gates from few ingredients and rich structure.

## Goal

- Focus on well-defined semantics for now, lowering later.

## Draft of the preliminary High Level Entry Point Dialect

### Type System

- Informed by, but not realizing in full, Linear Homotopy Type Theory.
- Denotational semantic model: A type is a finite-dimensional $\mathbb{C}$-vector bundle over a finite set, e.g. $$H_{\bullet} \equiv\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} : \text{Type},$$where $W$ is a finite set and $H_{\bullet}$ is a $W$-indexed family of finite-dimensional $\mathbb{C}$-vector spaces.
- We are only concerned with pure functions. A function $$
  f: \begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \to \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix}
  $$is given by a classical part $f_{\text{cl}}:W\to W'$, together with a $W$-family of linear maps $f_{\text{lin},w}:H_{w}\to H_{f_{\text{cl}}(w)}$.
- Purely classical types $W$ are embedded into this type system as covered by the Zero space, and purely linear types $H$ (i.e. vector spaces) cover the singleton: $$
  W \equiv\begin{bmatrix}
  0_{\bullet} \\ \downarrow \\ W
  \end{bmatrix},\qquad H \equiv\begin{bmatrix}
  H \\ \downarrow \\ *
  \end{bmatrix}.
  $$However, in order classical types to interact meaningfully with quantum types (e.g. by measurement), they need to be embedded into the quantum context. To this end, they are commonly equipped with an "infinitesimal halo" of linearity, which means they are covered by the tensor unit $\mathbb{C}$: $$
  \mathbb{C} \times W \equiv\begin{bmatrix}
  \mathbb{C}_{\bullet} \\ \downarrow \\ W
  \end{bmatrix}.
  $$This can be thought of as a classical type, together with a quantum phase.
- Types can be constructed in the following ways:
  - Cartesian product:$$\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \times \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \equiv \begin{bmatrix}H_{\bullet} \oplus H'_{\bullet} \\ \downarrow \\ W\times W'\end{bmatrix}, \quad \text{Unit: }\begin{bmatrix}0 \\ \downarrow \\ *\end{bmatrix}$$This represents independent quantum systems. It will be avoided by our IR.
    **Question:** Can we really avoid it?
  - Linear product:$$\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \otimes \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \equiv \begin{bmatrix}H_{\bullet} \otimes  H'_{\bullet} \\ \downarrow \\ W\times W'\end{bmatrix}, \quad \text{Unit: }\begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix}$$This represents the ordinary tensor product on purely linear types, and the cartesian types on _classical types with linear halo_. This product will be used implicitly throughout the IR in quantum context.
  - Coproduct/Sum:$$\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \sqcup \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \equiv \begin{bmatrix}H_{\bullet} \sqcup  H'_{\bullet} \\ \downarrow \\ W \sqcup W'\end{bmatrix}, \quad \text{Unit: }\begin{bmatrix} \emptyset \\ \downarrow \\ \emptyset\end{bmatrix}$$This behaves similar to ordinary sum types.
    **Question:** Do we have explicit ways to deal with this in our IR?
  - Linearization:$$\text{Lin}\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \equiv \begin{bmatrix}\bigoplus_{w:W} H_{w} \\ \downarrow \\ *\end{bmatrix}$$This turns a mixed type into a purely linear type. The operation is idempotent. Crucially, it transforms classical types with linear halo into the vector space whose basis is the classical set, but it destroys classical types without linear halo: $$\text{Lin}\begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ W\end{bmatrix} \equiv \begin{bmatrix}\mathbb{C}W \\ \downarrow \\ *\end{bmatrix}, \qquad \text{Lin}\begin{bmatrix}0_{\bullet} \\ \downarrow \\ W\end{bmatrix} \equiv \begin{bmatrix}0 \\ \downarrow \\ *\end{bmatrix}.$$**IR Realization:** `!prelim_hlep.lin<W>`

### Core Attributes and Ops

#### Functions in linear context

`func.func` can be decorated with a new singleton attribute `LinearHalo`. Within such functions:

- All classical types are implicitly treated as having a linear halo.
  - Remark: Mathematically, this operation is hard to motivate and does not have nice properties. However, the point here is one of convenience: Rather than requiring an additional wrapping of all classical values to explicitly move them into the quantum context, we infer this intent within a function that _has_ quantum-ness.
    We can use the restricted nature of term formation to get around the awkwardness of checking a type for classicality by inspecting the fibers: Instead, we constructively define all types arising from $\text{Lin}$ via some product combination as non-classical.
    **Question:** Does this work well in practice?
  - One special case is that of the singleton. It gets transformed into a pure halo. It is important that a halo'ed function does not have zero arguments.
- Coexisting terms live in the linear product of their types.
  - In particular, in the signature of a haloed function, comma-separation stands for the tensor product.
- Values that are not purely classical (with halo) must have precisely one use. - Enforced by validation using control flow analysis.
  **IR Realization:** `func.func @my_func() -> ... attributes { prelim_hlep.halo }`

#### (Partial) Linearization

Partial Linearization is a way to make operations more linear.
Given a function between product types

$$
f: \begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \otimes \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \to \begin{bmatrix}K_{\bullet} \\ \downarrow \\ V\end{bmatrix} \otimes \begin{bmatrix}K'_{\bullet} \\ \downarrow \\ V'\end{bmatrix},
$$

partial linearization (by convention always on the left tensor factors) gives a map

$$
\phi:M(f) \quad\vdash\quad \text{Lin}f: \text{Lin}\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \otimes \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \to \text{Lin}\begin{bmatrix}K_{\bullet} \\ \downarrow \\ V\end{bmatrix} \otimes \begin{bmatrix}K'_{\bullet} \\ \downarrow \\ V'\end{bmatrix},
$$

formally dependent on the measurement result $\phi$, which may take values in the set

$$
M(f) \equiv \text{Im}\left( w \mapsto \left(  w' \mapsto \text{pr}_{V'}\left( f_{\text{cl}} (w, w') \right) \right)  \right).
$$

In practice, $M(f)$ will be a product of bit-sets to be measured, or a quotient thereof. Note that there is a surjection-injection-factorization

$$
W \xtwoheadrightarrow{\pi} M(f) \xhookrightarrow{\iota} (W' \to V'),
$$

the last expression denoting the set of functions from $W'$ to $V'$.
Writing out the tensor products, we define

$$
\phi:M(f) \quad\vdash\quad \text{Lin}f: \begin{bmatrix}\bigoplus_{w:W}H_{w} \otimes H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix}  \to \begin{bmatrix}\bigoplus_{v:V}K_{v} \otimes K'_{\bullet} \\ \downarrow \\ V'\end{bmatrix}
$$

via

$$
\text{Lin}f_{\text{cl}} \equiv \iota(\phi)
$$

for the classical part, and in matrix elements $(\text{Lin}f_{\text{lin},w'})_{w,v}: H_{w} \otimes H'_{w'} \to K_{v} \otimes K'_{\text{Lin}f_{\text{cl}}(w')}$ via

$$
(\text{Lin}f_{\text{lin},w'})_{w,v} \equiv \delta_{\pi(w),\phi}\delta_{v,\text{pr}_{V}(f_{\text{cl}}(w,w'))}\;f_{\text{lin},w,w'}.
$$

for the linear fibers.

**IR Realization:**

```mlir
%in_lin = some.op : !prelim_hlep.lin<A>
%in_capture = some.op : <B>

%out_lin, %out_auxiliary = prelim_hlep.lin (
	%in_delinearized: <A> from %in_lin: !prelim_hlep.lin<A>, ...
) -> (!prelim_hlep.lin<C>, <D>, ...) {
	%out_delinearized, %out_aux =
		some.op (%in_delinearized, %in_capture) : (<A>, <B>) -> (<C>, <D>)
	prelim_hlep.output (%out_lin) carrying (%out_aux)
}
```

##### Example: X-gate

##### Example: Measurement

##### Example: Copying

##### Example: Deleting

##### Example: Controlled Gate

##### Consistency: Composition of linearization ops

- Has to be semantically equivalent.
- Demonstrate possible combined worlds project into singular worlds.

Given maps

$$
\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \otimes \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \xrightarrow{\quad f\quad} \begin{bmatrix}K_{\bullet} \\ \downarrow \\ V\end{bmatrix} \otimes \begin{bmatrix}K'_{\bullet} \\ \downarrow \\ V'\end{bmatrix}\xrightarrow{\quad g\quad} \begin{bmatrix}L_{\bullet} \\ \downarrow \\ X\end{bmatrix} \otimes \begin{bmatrix}L'_{\bullet} \\ \downarrow \\ X'\end{bmatrix},
$$we need to show that, in some sense, $$
\text{Lin}\,g \;\circ \text{Lin}\,f \;=\;\text{Lin}(g\circ f).
$$This by itself is not a well-defined equation since the terms are dependent: We are given
$$

\phi:M(f) \;\vdash\; \text{Lin}f,\quad \psi:M(g) \;\vdash\; \text{Lin}\,g,\quad \text{and} \quad \rho:M(g\circ f) \;\vdash\; \text{Lin}(g\circ f).

$$
As such, we can form
$$

(\phi, \psi):M(f) \times M(g) \;\vdash\; \text{Lin}f \circ \text{Lin}\,g.

$$
We would like to relate this pair of measurement results to the single measurement result $\rho:M(g\circ f)$ of the joint linearization. Note that we cannot expect to find a map $M(f) \times M(g) \to M(g \circ f)$: Some values $(\phi,  \psi)$ may impossible and will never be measured. These combinations do not have a corresponding measurement result in the joint space.
We therefore define **possible measurement combinations** as those pairs $(\phi,  \psi)$ for which there exists $\rho:M(g\circ f)$ such that
$$

\iota*{g \circ f} (\rho) = \iota*{g}(\psi) \circ \iota\_{f}(\phi) \; : \; W' \to X'.

$$
Due to injectivity of the inclusion, $\rho$ is unique if it exists.
More formally, the set $M(f) \times_{\text{poss}} M(g)$ of possible measurement combinations is the pullback of the diagram
$$

M(f) \times M(g) \xrightarrow{\iota*{f} \times \iota*{g}} ((W' \to V') \times (V' \to X')) \xrightarrow{-\circ-} (W' \to X') \xleftarrow{\iota\_{g\circ f}} M(g \circ f).

$$
This constructs a map
$$

\text{fuse}: M(f) \times\_{\text{poss}} M(g) \to M(g\circ f)

$$
**TODO:** Is $\text{fuse}$ surjective?
We therefore consider $f$ and $g$ as above in the context $(\phi,\psi):M(f) \times_{\text{poss}} M(g)$ and would like to prove (now more precisely):
$$

(\phi,\psi):M(f) \times*{\text{poss}} M(g)\quad \vdash \quad \text{Lin}\,g*{\psi} \;\circ \text{Lin}\,f*{\phi} \;=\;\text{Lin}(g\circ f)*{\text{fuse}(\phi,\psi)}.

$$
From the definitions we immediately get
$$

\text{Lin}g*{\psi,\text{cl}} \circ \text{Lin}f*{\phi,\text{cl}} \equiv \iota*{g}(\psi) \circ \iota*{f}(\phi) = \iota*{g \circ f} (\text{fuse}(\phi, \psi)) = \text{Lin}(g \circ f)*{\text{fuse}(\phi,\psi),\text{cl}}.

$$
on the base space. In fibers, we need to check that the following equality of linear maps
$$

H*{w} \otimes H'*{w'} \to L*{x} \otimes L'*{\text{Lin}(g \circ f)\_{\text{fuse}(\phi,\psi),\text{cl}}}

$$
holds in terms of matrix elements for all $w:W, w':W', \text{ and }x:X$: (Slightly abusing notation for readability $\phi = \text{Lin}f_{\phi,\text{cl}} : W' \to V'$ and introducing $\tilde{\phi} = \text{pr}_{V}f_\text{cl}(-,w') : W \to V$.)
$$\begin{align}
&\left(  \text{Lin}g_{\text{lin},\tilde{\phi}(w)} \circ \text{Lin}f_{\text{lin},w'}  \right)_{w,x}
= \sum_{v:V}\left(  \text{Lin}g_{\text{lin},\tilde{\phi}(w)} \right)_{v,x} \circ \left(\text{Lin}f_{\text{lin},w'}  \right)_{w,v}\\
&\quad\equiv \sum_{v:V} \delta_{\pi(\tilde{\phi}(w)), \psi} \delta_{x, \text{pr}_{X}(g_{\text{cl}}(v,\tilde{\phi}(w)))}\; \delta_{\pi(w'), \phi} \delta_{v, \text{pr}_{V}(f_{\text{cl}}(w,w'))} \;g_{\text{lin},v,\tilde{\phi}(w)} \circ f_{\text{lin},w,w'}
\\&\quad= \delta_{\pi(\tilde{\phi}(w)), \psi} \delta_{x, \text{pr}_{X}(g_{\text{cl}}(\text{pr}_{V}(f_{\text{cl}}(w,w')),\tilde{\phi}(w)))}\; \delta_{\pi(w'), \phi} \;g_{\text{lin},\text{pr}_{V}(f_{\text{cl}}(w,w')),\tilde{\phi}(w)} \circ f_{\text{lin},w,w'}
\\&\quad= \delta_{\pi(\tilde{\phi}(w)), \psi} \delta_{x, \text{pr}_{X}(g_{\text{cl}}(\text{pr}_{V}(f_{\text{cl}}(w,w')),\tilde{\phi}(w)))}\; \delta_{\pi(w'), \phi} \;(g \circ f)_{\text{lin},w,w'}
\\&\quad= \delta_{\pi(\tilde{\phi}(w)), \psi} \delta_{x,\text{pr}_{X}((g\circ f)_{\text{cl}}(w,w'))}\; \delta_{\pi(w'), \phi} \;(g \circ f)_{\text{lin},w,w'}
\\&\quad= \delta_{\pi(w'),\text{fuse}(\phi,\psi)}\delta_{x,\text{pr}_{X}((g\circ f)_{\text{cl}}(w,w'))}\;(g \circ f)_{\text{lin},w,w'}
\\&\quad= \left(  \text{Lin}(g\circ f)_{\text{lin},w'} \right)_{w,x}.
\end{align}
$$

##### Lowering Strategy

- Likely not all ops can be lowered at the start.
- First possibility: Direct lowering
  - Shave off ops at the boundary and lower those ops.
- Second possibility: Lower to specialized ops within HLEP
- Non-invertible linear maps:
  - Automatic block encoding (non-deterministic)
  - Synthesized Uncomputation

##### Optimization Strategy

- Merge linearization ops as much as possible, then perform classical optimization

#### Exponential map

The exponential map obtains a unitary operator from a Lie algebra element and a real number.
It is available only for purely quantum types, which we identify via the linearization functor.
In addition, we only support the Lie algebras $\text{su}(2^n)$, so the only allowed types are $\text{Lin}\begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}^n \end{bmatrix}$, or `i<n>` in IR syntax.
The Lie algebra element is given in the basis of Pauli products:

$$
\text{su}(2^n) = \text{span}\left( \{\sigma_{1} \otimes \dots \otimes \sigma_{n}\} \setminus \{\text{id}\}, \quad \sigma_{1},\dots,\sigma_{n}\in \{\sigma_{X},\sigma_{Y},\sigma_{Z}\}\right)
$$

**Question:** Should we instead use $\text{u}(2^n)$?
In IR, we write

```mlir
#operator = prelim_hlep.hamiltonian<3, X[0] * Y[2] + 1.5 * Z[1]>
```

for

$$
\text{operator} = \sigma_{X} \otimes \text{id} \otimes \sigma_{Y} + 1.5\; \text{id}\otimes \sigma_{Z}\otimes \text{id} \in \text{su}(2^3).
$$

Verification or canonicalization should ensure a proper form.

**IR Realization:**

```mlir
%out_state = prelim_hlep.exp %param hamiltonian<1, X[0] + Y[0]> %in_state :
	(f64, !prelim_hlep.lin<i1>) -> !prelim_hlep.lin<i1>
```

##### Example: Rotation gate

##### Example: GZZ gate

##### Lowering Strategy

One can start by only supporting basic rotation gates.
The problem of unitary synthesis is well-known.

##### Optimization Strategy

- Merge exponentiation of linearly dependent hamiltonians.
