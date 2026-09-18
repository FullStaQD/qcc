# The Preliminary High Level Entry Point

We would like to incorporate as an entry point to the compilation pipeline an IR specification which is

- high-level,
- hybrid, and
- broad.

In this document, we first outline our requirements of the entry point. This IR specification may correspond to one or more MLIR dialects. We refer to “the high-level dialect” as this IR specification, while keeping the question open whether it will actually be implemented as a dialect.

Secondly, we lay out a proposal for the entry point, realized as the `PrelimHLEP` dialect.

## Requirements

### High Level

#### Abstractions

The hybrid type category most likely has three relevant operations to construct types:

- Coproduct (sum)
- Cartesian product (classical product, quantum direct sum)
- Linear product (classical product, quantum tensor product)

From these building blocks, one should be able to construct new types that only exist at compile time and cause no runtime overhead.

In addition, one can consider generics (possibly in the form of dependent types), interfaces (abstract base classes, traits, something like this), or other abstractions.

Ideally, abstractions should be zero-cost.

#### Rigorous type system capturing quantum logic

On lower level quantum programming, there is a tradeoff related to the distinction between pointer and value semantics:

- Instructions at the lowest level are purely imperative. It is impossible to write an incorrect program in an assembly language, but the flow of (quantum) information is highly obscured.
- In a value-semantic IR, the flow of information is more tractable. However, in order to implement such an IR, it is important to base it on a well-defined logic. Otherwise, one has invalid programs. This is especially true for the flow of quantum information, where linear logic poses additional constraints on variables.

We want to faithfully capture the flow of hybrid quantum-classical information. To certify that a program is even physical, the language it is written in needs to be based in a hybrid type theory.

A rich type theory will allow higher order concepts, such as dependent types, (hybrid) function types, or even identity types, the latter allowing for certification of the correctness of programs.

Embedding a linear aspect into a type theory requires some form of bookkeeping, in the form of lifetimes, color palettes, or by another scheme.

### Hybrid

#### Structured classical control flow

Interaction with classical parts of the program should be seamless and ideally use existing technology (e.g. `cf`, `scf`, `affine` dialects).

#### Structured quantum control flow

Controlled gates have a clear meaning in terms of control flow. This has two implications:

- Rather than introducing controlled gates, the dialect should have structured “quantum if” operations that are common across high-level quantum languages.
- The knowledge about the control-flow interpretation should be encoded in the dialect. This refines the picture of the flow of hybrid information and allows for better optimizations. This is already implemented in:
  - Nvidia’s `quake` dialect, where control-wires are typed differently from regular wires, and
  - the `unqomp` algorithm for automated uncomputation.
    In both cases, the control-wires are multi-edges and break linearity, exploiting the z-commutativity property of controlled gates on the control qubits.

#### Linearization of classical types

One possibility for introducing quantum types is to provide a quantization generic, which transforms a classical type into the quantum type that has the classical value set as a distinguished basis.

This avoids the careful introduction of quantum base types and opens the door to a monadic programming paradigm, as well as just-a-phase-style gate definitions.

Keeping the underlying classical types explicit, one could also define quantizations of classical functions, which result in free quantum functions that play an important role in `silq` (called "`qfree`" there).

### Broad

#### Existing and proposed high-level languages can be embedded

MLIR’s full potential is best leveraged if as much of the lowering as possible happens within the framework. Ideally, the passing from a high-level language to the MLIR entry dialect is only a syntactic translation, not a semantic lowering.

To meet this goal with multiple frontends, expecting newly developed ones in the future, the high-level dialect must be able to faithfully capture the language concepts of all supported input languages. It is of course hard to predict how a possible future frontend language will look like. However, the following observation helps.

Currently, the space of quantum programming languages is divided into

- low- and mid-level ad-hoc languages that are actually used and have a strong reference implementation,

- high-level languages based on solid theoretical foundations that are academic research objects and are either not implemented or ignored by the practitioner community.

More recently, frameworks like `qrisp` sit somewhere between these groups and can be seen as a step towards higher-level languages actually being realized.

If we are able to capture `qrisp` alongside the essential concepts of the most promising high-level languages in the dialect, the chance is high that it will support a well-designed future frontend language. In particular, we should consider:

- From qrisp:
  - Quantum versions of:
    - `Float` (misnomer, really fixed-point rationals).
    - `Bool`
    - `Modulus`, e.g. `Float mod 2pi`.
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

#### Syntactic sugaring for common concepts

- Automatic uncomputation is a common feature of high-level programming languages. If it is implicit, linearity will be broken on the highest level.
- Just-a-phase style if-let statements are a neat way to define gates from few ingredients and rich structure.

## Draft of the preliminary High Level Entry Point Dialect

Guided by the requirements above, we focus for now on well-defined semantics, leaving lowering for later. Informally, a hybrid type in this model is a classical set of labels, each label carrying its own quantum state space (a finite-dimensional Hilbert space).
Purely classical and purely quantum types are the special cases where all state spaces are trivial or where there is a single label, respectively.
The formal model below makes this precise as a finite-dimensional $\mathbb{C}$-vector bundle over a finite set.
We only give **denotational semantics** -- meaning we describe what mathematical concepts the language constructs correspond to. We don't provide a type theory here, and we don't give operational semantics.

### Philosophy

We observe that the unitary operations forming quantum circuits arise -- in mathematical theory and quantum computing practice alike -- by means of only few paths:

- A (often simple, in some sense) Lie group element is exponentiated.
  Examples include all so-called "rotation" gates, (global) phase shifts, S and T.
- A classical, combinatorial function is freely linearized
  Examples in the Z-basis are the X, Z, SWAP, and CNOT gates.
- Base-change gates.
  In particular, the Hadamard gate.

In addition, some gates are combinations, such as controlled-rotation gates.
Each one of the construction paths comes with its own theory and ways to reason about the resulting unitaries.
They should therefore be manifestly present in a high-level IR.

### Type System

The type system is informed by, but does not realize in full, Linear Homotopy Type Theory.

#### Vector bundles over finite sets

The semantic model below is phrased in terms of vector bundles.
A _vector bundle over a finite set_ $W$ is nothing more than a $W$-indexed family of vector spaces: for every element $w : W$, a finite-dimensional $\mathbb{C}$-vector space $H_w$, called the _fiber_ over $w$. We picture the _base_ set $W$ drawn horizontally, with the fiber $H_w$ attached vertically over each point, and write

$$
\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix}
$$

for the whole datum. In many instances, the all fibres will be equal ($H_w \equiv H_{w'}$ for any $w$, $w'$).

Note the direction of information flow: along a single morphism, the classical part cannot depend on the quantum data. Measurement — the creation of classical data out of quantum data — is therefore _not_ a single bundle morphism. It is a whole family of morphisms indexed by the possible outcomes; capturing this is exactly what the hypothetical-judgment notation $\phi : M(f) \vdash \text{Lin}\,f$ is for, and it is the technical heart of the linearization machinery below.

#### Semantics

- Denotational semantic model:
  A type is a finite-dimensional $\mathbb{C}$-vector bundle over a finite set, e.g. $$H_{\bullet} :\equiv\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} : \text{Type},$$where $W$ is a finite set and $H_{\bullet}$ is a $W$-indexed family of finite-dimensional $\mathbb{C}$-vector spaces.
  The physical reading is what makes this the right notion for hybrid programs:

  - The base set $W$ enumerates the possible values of the _classical_ data: the contents of a classical register, or the outcomes of the measurements performed so far. The model lends itself to a many-worlds view in which we allow ourselves to think of elements of $W$ (measurement results) as _possible worlds_.
  - The _fiber_ $H_w$ is the Hilbert space of the _quantum_ data in the branch (world) where the classical data reads $w$. The fiber may genuinely depend on $w$: in the branch where a measurement came out $1$, the program may have discarded or allocated qubits.
  - A term of such a type is a base point $w$ together with a vector $\xi : H_w$ — definite classical data, quantum data conditioned on it.

- We are only concerned with pure functions. A function
  $$
  f: \begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \to \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix}
  $$
  is given by a classical part $f_{\text{cl}}:W\to W'$, together with a $W$-family of linear maps $f_{\text{lin},w}:H_{w}\to H_{f_{\text{cl}}(w)}$.
  Such a function is called a _bundle morphism_; that it is applicable to hybrid computation is one reason why we choose to formalize the types as bundles, not merely families of vector spaces.
- Purely classical types $W$ are embedded into this type system as covered by the Zero space, and purely linear types $H$ (i.e. vector spaces) cover the singleton:
  $$
  W :\equiv\begin{bmatrix}
  0_{\bullet} \\ \downarrow \\ W
  \end{bmatrix},\qquad H :\equiv\begin{bmatrix}
  H \\ \downarrow \\ *
  \end{bmatrix}.
  $$
  However, in order for classical types to interact meaningfully with quantum types (e.g. by measurement), they need to be embedded into the quantum context. To this end, they are commonly equipped with "linear vacuum", which means they are covered by the tensor unit $\mathbb{C}$:
  $$
  \mathbb{C} \times W :\equiv\begin{bmatrix}
  \mathbb{C}_{\bullet} \\ \downarrow \\ W
  \end{bmatrix}.
  $$
  This can be thought of as a classical type, together with a quantum phase.
- Types can be constructed in the following ways:
  - Cartesian product:
    $$
    \begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \times \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} :\equiv \begin{bmatrix}H_{\bullet} \oplus H'_{\bullet} \\ \downarrow \\ W\times W'\end{bmatrix}, \quad \text{Unit: }\begin{bmatrix}0 \\ \downarrow \\ *\end{bmatrix}
    $$
    On the classical bases this is the ordinary pair type. On the quantum fibers, however, it takes the direct sum rather than the tensor product, so it does _not_ describe the joint state space of two coexisting quantum systems (that is the linear product below): a fiber vector is a superposition of "the quantum data lives in the left summand" and "… in the right summand" — an additive either/or, the biproduct of linear logic. It will be avoided by our IR.
  - Linear product:
    $$\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \otimes \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} :\equiv \begin{bmatrix}H_{\bullet} \otimes  H'_{\bullet} \\ \downarrow \\ W\times W'\end{bmatrix}, \quad \text{Unit: }\begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix}$$
    This represents the ordinary tensor product on purely linear types, and the Cartesian product on _classical types with linear halo_. This product will be used implicitly throughout the IR in quantum context.
  - Coproduct/Sum:
    $$\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \sqcup \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} :\equiv \begin{bmatrix}H_{\bullet} \sqcup  H'_{\bullet} \\ \downarrow \\ W \sqcup W'\end{bmatrix}, \quad \text{Unit: }\begin{bmatrix} \emptyset \\ \downarrow \\ \emptyset\end{bmatrix}$$
    This behaves similar to ordinary sum types. (Open question on IR support for this constructor — see "Open Questions / TODOs" below.)
  - Linearization:
    $$\text{Lin}\,\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} :\equiv \begin{bmatrix}\bigoplus_{w:W} H_{w} \\ \downarrow \\ *\end{bmatrix}$$
    This turns a mixed type into a purely linear type. The operation is idempotent. Crucially, it transforms classical types with linear halo into the vector space whose basis is the classical set, but it destroys classical types without linear halo:
    $$\text{Lin}\,\begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ W\end{bmatrix} \equiv \begin{bmatrix}\mathbb{C}W \\ \downarrow \\ *\end{bmatrix}, \qquad \text{Lin}\,\begin{bmatrix}0_{\bullet} \\ \downarrow \\ W\end{bmatrix} \equiv \begin{bmatrix}0 \\ \downarrow \\ *\end{bmatrix}.$$
    **IR Realization:** `!prelim_hlep.lin<W>`

### Core Attributes and Ops

#### Functions in linear context

`func.func` can be decorated with a new singleton attribute `LinearHalo`. Within such functions:

- All classical types are implicitly treated as having a linear halo.
  - The point here is one of convenience: Rather than requiring an additional wrapping of all classical values to explicitly move them into the quantum context, we infer this intent within a function that _has_ quantum-ness.
    We can use the restricted nature of term formation to get around the awkwardness of checking a type for classicality by inspecting the fibers: Instead, we constructively define all types arising from $\text{Lin}$ via some product combination as non-classical.
  - One special case is that of the singleton. It gets transformed into a pure halo. It is important that a halo'ed function does not have zero arguments.
- Coexisting terms live in the linear product of their types.
  - In particular, in the signature of a haloed function, comma-separation stands for the tensor product.
- Values that are not purely classical (with halo) must have precisely one use. - Enforced by validation using control flow analysis.
  Halo'ed functions could also be called quantum kernels. Some remarks on consistency and well-defined-ness:
- Equipping a purely classical value with a halo is a monoidal functor, transforming cartesian products to linear products.
- When a halo'ed function calls a regular function $f$, this is interpreted as a call of $\mathbb{C} \times f$.
- When a regular function calls a halo'ed function, the arguments and return values are wrapped with the unit/counit $W \to \mathbb{C} \times W \to W$. Note that non-classical values are not allowed in regular functions. This semantic wrapping is not visible in IR.
- We lose the ability to express purely classical values in halo'ed functions, but their halo'ed counterparts are just as expressive. We would have nothing to gain from this, as having just one classical term coexisting with linear terms would render all terms classical by definition of the linear product.
  **IR Realization:** `func.func @my_func() -> ... attributes { prelim_hlep.halo }`

#### Halo Unit Type

Ordinary `mlir` has a builtin unit type `none`. Generic, dialect-agnostic optimizations are free to treat any value of that type as carrying no information at all. This is correct for a purely classical unit.

It is not correct for the halo'ed unit. Recall that the tensor unit of the linear product is

$$
\begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix},
$$

i.e. a $1$-dimensional Hilbert space over the single classical label $*$. A term of this type is a complex scalar, which we also view as a phase, since we don't usually care about the modulus.
Classically this phase is invisible, but once the term is combined, via the linear product, with other haloed or quantum values (e.g. inside an `scf.if` branch, cf. the Controlled Gate example below), that phase becomes a _relative_ phase between branches, which is observable through interference. A generic optimizer that reuses `mlir`'s builtin unit type for this purpose could legally dead-code-eliminate a "do-nothing" value that is in fact carrying exactly the phase information a computation depends on.

On the flipside, the unique value of `none` type is implicitly left out of IR.
A function with "no arguments" really is a function with a single argument `%none: none`.
When `none` becomes halo'ed, it is important to track the actual value.

We therefore introduce a dedicated type `!prelim_hlep.unit`, opaque to generic optimizations, for exactly this fiber bundle.
Halo'ed functions are not allowed to have no arguments or no returns, instead they should take in or put out a `!prelim_hlep.unit`.

**IR Realization:** `!prelim_hlep.unit`

```mlir
func.func @global_phase(%halo: !prelim_hlep.unit) -> !prelim_hlep.unit attributes { prelim_hlep.halo } {
  %phase_change = some.op : complex<f32>
	%phased = prelim_hlep.scale %phase_change, %halo : (complex<f32>, !prelim_hlep.unit) -> !prelim_hlep.unit
	return %phased : !prelim_hlep.unit
}

// Call from classical function:
func.func @main() {
  %halo = prelim_hlep.unit_value : !prelim_hlep.unit
  %out_halo = func.call @global_phase(%halo) : (!prelim_hlep.unit) -> !prelim_hlep.unit
  // out_halo can be forgotten.
}
```

Strictly speaking, the semantic interpretation of `!prelim_hlep.unit` is that it is equal to the `none` type: It is an actual unit type in a classical function, and, as a classical type, implicitly halo'ed in halo'ed functions.

#### Scale, AddPhase

Within halo'ed functions, it is legal to scale all fibers of a type homogeneously by a complex factor.
We moreover provide the shortcut operation `add_phase` that scales by the exponent of a purely imaginary number.

**IR Realization:**

- `prelim_hlep.scale %factor, %t : (complex<f64>, T) -> T`
- `prelim_hlep.add_phase %alpha, %t : (f64, T) -> T`

#### (Partial) Linearization

Partial Linearization is a way to make operations more linear.
Given a function between product types

$$
f: \begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \otimes \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \to \begin{bmatrix}K_{\bullet} \\ \downarrow \\ V\end{bmatrix} \otimes \begin{bmatrix}K'_{\bullet} \\ \downarrow \\ V'\end{bmatrix},
$$

partial linearization (by convention always on the left tensor factors) gives a map

$$
\phi:M(f) \quad\vdash\quad \text{Lin}\,f: \text{Lin}\,\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \otimes \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \to \text{Lin}\,\begin{bmatrix}K_{\bullet} \\ \downarrow \\ V\end{bmatrix} \otimes \begin{bmatrix}K'_{\bullet} \\ \downarrow \\ V'\end{bmatrix},
$$

i.e. a family of maps in the context of a measurement result $\phi$, whose type is

$$
M(f) :\equiv \text{Im}\left( w \mapsto \left(  w' \mapsto \text{pr}_{V'}\left( f_{\text{cl}} (w, w') \right) \right)  \right).
$$

In practice, $M(f)$ will be a product of bit-types to be measured, or a quotient thereof. Note that there is a surjection-injection-factorization

$$
W \xtwoheadrightarrow{\pi} M(f) \xhookrightarrow{\iota} (W' \to V'),
$$

the last expression denoting the function type from $W'$ to $V'$.
Writing out the tensor products, we define

$$
\phi:M(f) \quad\vdash\quad \text{Lin}\,f: \begin{bmatrix}\bigoplus_{w:W}H_{w} \otimes H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix}  \to \begin{bmatrix}\bigoplus_{v:V}K_{v} \otimes K'_{\bullet} \\ \downarrow \\ V'\end{bmatrix}
$$

via

$$
\text{Lin}\,f_{\text{cl}} :\equiv \iota(\phi)
$$

for the classical part, and in matrix elements $(\text{Lin}\,f_{\text{lin},w'})_{w,v}: H_{w} \otimes H'_{w'} \to K_{v} \otimes K'_{\text{Lin}\,f_{\text{cl}}(w')}$ via

$$
(\text{Lin}\,f_{\text{lin},w'})_{w,v} :\equiv \delta_{\pi(w),\phi}\,\delta_{v,\text{pr}_{V}(f_{\text{cl}}(w,w'))}\;f_{\text{lin},w,w'}
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
	prelim_hlep.output (%out_delinearized) carrying (%out_aux)
}
```

Crucially, $M(f)$ or its terms are not part of the IR. $M(f)$ encodes the different possible worlds the particular program could end up in after execution. It is still possible to obtain a measurement result as an IR value, but this will appear as a term of $V'$ (or `%out_aux : <D>` in this example). See also the measurement example below.

##### Example: X-gate

We start with

$$
f: \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix} \otimes \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix} \otimes \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix},
$$

$$
f_{\text{cl}} :\equiv \text{NOT}: \{0,1\} \to \{0,1\}
$$

with identities on fibers.
We observe that

$$
M(f) :\equiv \text{Im}\left( b \mapsto \text{pr}_{*}\left( f_{\text{cl}} (b) \right)  \right)
$$

is a singleton. This tells us that no measurement is necessary to realize the program.
Partial linearization yields a map (omitting the unit tensor factors)

$$
*:M(f) \quad\vdash\quad \text{Lin}\,f: \begin{bmatrix}\mathbb{C}\{0,1\} \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C}\{0,1\}\\ \downarrow \\ *\end{bmatrix},
$$

with unique fiber given as

$$
(\text{Lin}\,f_{\text{lin},*})_{w,v} = \delta_{\pi(w),*}\,\delta_{v,\,\text{NOT}(w)}\;\text{id}_{\mathbb{C}}
\qquad (w,v : \{0,1\}),
$$

where $\pi:\{0,1\}\to *$ is the unique map, so the first Kronecker delta is identically $1$. The map therefore sends $\ket{w} \mapsto \ket{\text{NOT}(w)}$, i.e. $\ket{0}\mapsto\ket{1}$, $\ket{1}\mapsto\ket{0}$, which is the Pauli-$X$ gate.

**IR Realization:**
An X-gate is simply a full linearization of a classical not gate. (The `arith` dialect needs a helper constant.)

```mlir
%in_qubit = some.op : !prelim_hlep.lin<i1>

%out_qubit = prelim_hlep.lin (
	%in_delinearized: i1 from %in_qubit: !prelim_hlep.lin<i1>, ...
) -> (!prelim_hlep.lin<i1>) {
	%one = arith.constant 1 : i1
	%out_delinearized = arith.xor %in_delinearized, %one : i1
	prelim_hlep.output (%out_delinearized)
}
```

##### Example: Measurement

For a measurement, the order of the tensor factors is critical (even though we have tensor units), because partial linearization affects only the first tensor factor. The incoming bit of information will be linearized (qubit in, left tensor factor), while the outgoing information remains discrete (bit out, right tensor factor).

$$
f: \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix} \otimes \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix} \to\begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix} \otimes  \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix}.
$$

Up to structure morphisms $f_{\text{cl}}$ is the identity, and fiber maps are identities as well.
We find that

$$
M(f) :\equiv \text{Im}\left( b \mapsto \text{pr}_{\{0,1\}}\left( f_{\text{cl}} (b) \right)  \right) \equiv \text{Im}(\text{id}_{\{0,1\}}) = \{0,1\},
$$

exhibiting two possible worlds, which means that one measurement must take place for realization.
For the partially linearized map, we get

$$
b:M(f) \quad\vdash\quad \text{Lin}\,f: \begin{bmatrix}\mathbb{C}\{0,1\} \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix},
$$

where the classical part $\text{Lin}\,f_{\text{cl}}:* \to \{0,1\}$ is determined by $*  \mapsto b$, and on fibers

$$
(\text{Lin}\,f_{\text{lin},b})_{w,*} = \delta_{\pi(w),\,b}\,\delta_{*,\,*}\;\text{id}_{\mathbb{C}}
\qquad (w : \{0,1\}),
$$

where $\pi:\{0,1\}\to M(f)=\{0,1\}$ is the identity, so $\delta_{\pi(w),b}=\delta_{w,b}$. In world $b$, the fiber map $\mathbb{C}\{0,1\}\to\mathbb{C}$ is therefore the projection onto the $b$-th basis vector.

**IR Realization:**

```mlir
%in_qubit = some.op : !prelim_hlep.lin<i1>

%measurement_result = prelim_hlep.lin (
	%delinearized: i1 from %in_qubit: !prelim_hlep.lin<i1>, ...
) -> (i1) {
	prelim_hlep.output () carrying (%delinearized)
}
```

Even though $M(f)$ is non-trivial here, it does not show up in the IR. From the IR perspective, we simply get a `%measurement_result : i1` by some means. Semantically, the measurement outcome is a _constant depending on_ the possible world $b : M(f)$.

##### Example: Copying

It is not possible to copy linear information, but it is possible to linearize a classical copy operation. This will result in copying behavior on the basis states, and mixed behavior otherwise.

While this operation may not be interesting in practice, we demonstrate here that the formalism can unambiguously handle cases which might seem forbidden.
We start with

$$
f: \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix} \otimes \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}^2\end{bmatrix} \otimes \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix},
$$

$$
f_{\text{cl}} :\equiv \text{COPY}: \{0,1\} \to \{0,1\}^2
$$

with identities on fibers. We again find $M(f) = *$, implying no measurements are needed.
Upon (partial, but in this case full) linearization, we get a unique linear map on the fibers:

$$
(\text{Lin}\,f_{\text{lin},*})_{w,v} = \delta_{\pi(w),*}\,\delta_{v,\,(w,w)}\;\text{id}_{\mathbb{C}}
\qquad (w : \{0,1\},\; v : \{0,1\}^2),
$$

where $\pi:\{0,1\}\to *$ is the unique map. The map sends $\ket{w} \mapsto \ket{(w,w)}$.

In particular, we have $\ket{0} \mapsto \ket{00}, \ket{1} \mapsto \ket{11}$.

**IR Realization:**

```mlir
%in_qubit = some.op : !prelim_hlep.lin<i1>

%qubit_a, %qubit_b = prelim_hlep.lin (
	%delinearized: i1 from %in_qubit: !prelim_hlep.lin<i1>, ...
) -> (!prelim_hlep.lin<i1>, !prelim_hlep.lin<i1>) {
	prelim_hlep.output (%delinearized, %delinearized)
}
```

##### Example: Deleting

Deleting is the linearization of the classical discard map. We start with

$$
f: \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix} \otimes \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix} \otimes \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix},
$$

$$
f_{\text{cl}} :\equiv\; !_{\{0,1\}} : \{0,1\} \to *,
$$

the unique map into the terminal set, with identity on fibers. We find $M(f) = *$, so no measurement is needed. Partial (here full) linearization yields

$$
*:M(f) \quad\vdash\quad \text{Lin}\,f: \begin{bmatrix}\mathbb{C}\{0,1\} \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix},
$$

with fiber

$$
(\text{Lin}\,f_{\text{lin},*})_{w,*} = \delta_{\pi(w),*}\,\delta_{*,\,*}\;\text{id}_{\mathbb{C}} = \text{id}_{\mathbb{C}}
\qquad (w : \{0,1\}).
$$

The map sends basis states $\ket{b} \mapsto 1$.

**IR Realization:**

```mlir
%in_qubit = some.op : !prelim_hlep.lin<i1>

prelim_hlep.lin (
	%delinearized: i1 from %in_qubit: !prelim_hlep.lin<i1>, ...
) -> () {
	prelim_hlep.output ()
}
```

##### Example: Controlled Gate

A controlled-$U$ gate arises as the linearization of a classical branch on the control bit. The control qubit is delinearized (left tensor factor), while the target qubit is captured as a linear value (right tensor factor). We start with

$$
f: \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix} \otimes \begin{bmatrix}H' \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ *\end{bmatrix} \otimes \begin{bmatrix}H' \\ \downarrow \\ *\end{bmatrix},
$$

where $H' :\equiv \mathbb{C}^2$ is the target qubit. The classical part is forgetting the control (the identity would be an alternative),

$$
f_{\text{cl}} :\equiv\; !_{\{0,1\}} : \{0,1\} \to *,
$$

and the fiber maps branch on the control value:

$$
f_{\text{lin},b} :\equiv \begin{cases} U & b = 1 \\ \text{id}_{H'} & b = 0 \end{cases}.
$$

Since $W' = V' = *$, we have $M(f) = *$: no measurement is needed. Partial linearization yields

$$
*:M(f) \quad\vdash\quad \text{Lin}\,f: \begin{bmatrix}\mathbb{C}\{0,1\} \otimes H' \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix} H' \\ \downarrow \\ *\end{bmatrix},
$$

with fiber

$$
(\text{Lin}\,f_{\text{lin},*})_{w,*} = \delta_{\pi(w),*}\;f_{\text{lin},w} = f_{\text{lin},w}
\qquad (w : \{0,1\}).
$$

The map therefore acts as $\ket{0}\ket{\psi} \mapsto \ket{\psi}$, $\ket{1}\ket{\psi} \mapsto U\ket{\psi}$, which is a controlled-$U$ gate.

**IR Realization:**

```mlir
%control_qubit = some.op : !prelim_hlep.lin<i1>
%target_qubit = some.op : !prelim_hlep.lin<i1>

%out_target_qubit = prelim_hlep.lin (
	%control_bit: i1 from %control_qubit: !prelim_hlep.lin<i1>,
) -> (!prelim_hlep.lin<i1>) {
	%out_target = scf.if %control_bit {
		%modified_target = some.gate %target_qubit : !prelim_hlep.lin<i1>
		scf.yield %modified_target
	} else {
		scf.yield %target_qubit  // CFA must prove that this double use is exactly one use.
	}
	prelim_hlep.output (%out_target)
}
```

(Of course, other versions exist: return control qubit as well, delinearize target qubit as well (if the gate is free), ...)

##### Composition

Consistency of linearization ops under composition:

- Has to be semantically equivalent.
- Demonstrate possible combined worlds project into singular worlds.

Given maps

$$
\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \otimes \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \xrightarrow{\quad f\quad} \begin{bmatrix}K_{\bullet} \\ \downarrow \\ V\end{bmatrix} \otimes \begin{bmatrix}K'_{\bullet} \\ \downarrow \\ V'\end{bmatrix}\xrightarrow{\quad g\quad} \begin{bmatrix}L_{\bullet} \\ \downarrow \\ X\end{bmatrix} \otimes \begin{bmatrix}L'_{\bullet} \\ \downarrow \\ X'\end{bmatrix},
$$

we need to show that, in some sense,

$$
\text{Lin}\,g \;\circ \text{Lin}\,f \;\approx\;\text{Lin}\,(g\circ f).
$$

This by itself is not a well-defined equation since the terms are dependent: We are given

$$
\phi:M(f) \;\vdash\; \text{Lin}\,f,\quad \psi:M(g) \;\vdash\; \text{Lin}\,g,\quad \text{and} \quad \rho:M(g\circ f) \;\vdash\; \text{Lin}\,(g\circ f).
$$

As such, we can form

$$
(\phi, \psi):M(f) \times M(g) \;\vdash\; \text{Lin}\,g \circ \text{Lin}\,f.
$$

We would like to relate this pair of measurement results to the single measurement result $\rho:M(g\circ f)$ of the joint linearization. Note that we cannot expect to find a map $M(f) \times M(g) \to M(g \circ f)$: Some values $(\phi,  \psi)$ may be impossible and will never be measured, and conversely a single pair $(\phi,\psi)$ may be compatible with several joint outcomes $\rho$.

We therefore define **possible measurement combinations** existentially: a pair $(\phi, \psi) : M(f) \times M(g)$ is _possible_ iff there exist classical inputs $w:W$ and $w':W'$ that jointly witness both outcomes, i.e.

$$
\pi_f(w) = \phi \quad\text{and}\quad \pi_g\bigl(f_V(w, w')\bigr) = \psi,
$$

where $f_V :\equiv \text{pr}_V \circ f_{\text{cl}} : W \times W' \to V$ is the classical residue produced by $f$ on its left (linearized) factor, and $\pi_f, \pi_g$ are the surjections from $W$ (resp. $V$) onto $M(f)$ (resp. $M(g)$). We write $M(f) \times_{\text{poss}} M(g)$ for the type of possible pairs.

**Proposition (possible pairs are exactly the nonzero blocks).** Assume every fiber map $f_{\text{lin},w,w'}$ (and likewise for $g$) is nonzero — this holds whenever $f$, $g$ arise from genuine, non-degenerate quantum operations, e.g. built from unitaries or isometries. Then $(\phi,\psi)$ is possible iff $\text{Lin}\,g_\psi \circ \text{Lin}\,f_\phi \not\equiv 0$.

_Proof._ ($\Leftarrow$, contrapositive) If $(\phi,\psi)$ is not possible, then for every $w:W,\,w':W'$ at least one of $\delta_{\pi_f(w),\phi}$, $\delta_{\pi_g(f_V(w,w')),\psi}$ vanishes, so every matrix element of $\text{Lin}\,g_\psi \circ \text{Lin}\,f_\phi$ (cf. the fiber formula in the Composition Theorem below) is identically $0$, hence the map is $0$.
($\Rightarrow$) If $(\phi,\psi)$ is possible, witnessed by some $(w,w')$, the corresponding $w$-summand block of the composite is exactly $g_{\text{lin},f_V(w,w')} \circ f_{\text{lin},w,w'}$ (at $v = f_V(w,w')$) — no Kronecker delta kills it — which is nonzero by the non-degeneracy hypothesis. $\square$

Note the non-degeneracy hypothesis is necessary: without it, a witnessing block could still evaluate to the zero linear map by coincidence, without the pair being "impossible" in the measurement-theoretic sense above.

We define a **relation**

$$
(\phi,\psi) \sim \rho \quad\iff\quad \exists\, w:W,\, w':W':\; \pi_f(w)=\phi \;\land\; \pi_g\bigl(f_V(w,w')\bigr)=\psi \;\land\; \pi_{g\circ f}(w)=\rho,
$$

where $\pi_{g\circ f}: W \to M(g\circ f)$ is the surjection for the composite (note: a function of $w$ only, since $M(g\circ f) :\equiv \text{Im}\bigl(w \mapsto (w' \mapsto \text{pr}_{X'}((g\circ f)_{\text{cl}}(w, w')))\bigr)$). In words: $(\phi,\psi) \sim \rho$ iff some classical input $w$ (with some $w'$) simultaneously witnesses $\phi$ for $f$, $\psi$ for $g$, and $\rho$ for $g\circ f$.
We say that the pair $(w, w')$ _witnesses_ the compatibility $(\phi,\psi) \sim \rho$.

**The relation $\sim$ is surjective onto $M(g\circ f)$.** For any $\rho : M(g\circ f)$, surjectivity of $\pi_{g\circ f}: W \to M(g\circ f)$ yields $w:W$ with $\pi_{g\circ f}(w)=\rho$; picking any $w':W'$ and setting $\phi :\equiv \pi_f(w)$, $\psi :\equiv \pi_g(f_V(w,w'))$ gives $(\phi,\psi) \sim \rho$. $\square$

Note that $\sim$ need not be functional: the same pair $(\phi,\psi)$ may relate to distinct $\rho$'s, because the $\psi$-measurement cannot distinguish classical residues that the joint measurement distinguishes. We therefore cannot expect equality of morphisms $\text{Lin}\,g_{\psi} \circ \text{Lin}\,f_{\phi} = \text{Lin}\,(g\circ f)_{\rho}$ to hold in general. Instead, we evaluate on basis vectors compatible with the measurement results.

**Composition Theorem.** Let $(\phi,\psi) \sim \rho$ be witnessed by $(w, w')$, i.e., $\pi_f(w) = \phi$, $\pi_g(f_V(w, w')) = \psi$, and $\pi_{g\circ f}(w) = \rho$. Then for any term $\xi_w : H_w \otimes H'_{w'}$ (a term of the $w$-summand of the domain at base $w'$):

$$
(\phi,\psi) \sim \rho \text{ witnessed by } (w,w') \quad\vdash\quad \text{Lin}\,g_{\psi} \circ \text{Lin}\,f_{\phi}(\xi_w) \;=\; \text{Lin}\,(g\circ f)_{\rho}(\xi_w).
$$

By linearity, the maps agree on the subspace spanned by all compatible summands $H_w \otimes H'_{w'}$ (over all $(w,w')$ witnessing $(\phi,\psi)\sim\rho$). When $\sim$ is functional and the witnesses cover all of $W \times W'$, this subspace is the entire domain and we obtain equality of morphisms.

**Proof.** On the base space, the classical part of $\text{Lin}\,g_\psi \circ \text{Lin}\,f_\phi$ at $w'$ is $\iota_g(\psi) \circ \iota_f(\phi)(w')$. We evaluate:

$$
\begin{align}
\iota_g(\psi) \circ \iota_f(\phi)(w')
&= \iota_g(\psi)(v'), \quad v' :\equiv \text{pr}_{V'}(f_{\text{cl}}(w,w'))
&& \text{since } \pi_f(w) = \phi \\
&= \text{pr}_{X'}\bigl(g_{\text{cl}}(v, v')\bigr), \quad v :\equiv f_V(w,w')
&& \text{since } \pi_g(v) = \psi \\
&= \text{pr}_{X'}\bigl((g \circ f)_{\text{cl}}(w,w')\bigr)
&& (v, v') = f_{\text{cl}}(w,w') \\
&= \iota_{g\circ f}(\rho)(w')
&& \text{since } \pi_{g\circ f}(w) = \rho \\
&= \text{Lin}\,(g \circ f)_{\rho,\text{cl}}(w').
\end{align}
$$

In fibers, we evaluate on $\xi_w : H_w \otimes H'_{w'}$. (We keep $v' :\equiv \text{pr}_{V'}(f_{\text{cl}}(w,w'))$ from above; since $\pi_f(w) = \phi$, this is the base point $\text{Lin}\,f_{\phi,\text{cl}}(w') : V'$ over which the fiber map of $\text{Lin}\,g_\psi$ is taken.)

$$
\begin{align}
&\left(  \text{Lin}\,g_{\text{lin},v'} \circ \text{Lin}\,f_{\text{lin},w'}  \right)_{w}(\xi_w)
= \sum_{v:V}\left(  \text{Lin}\,g_{\text{lin},v'} \right)_{v} \circ \left(\text{Lin}\,f_{\text{lin},w'}  \right)_{w,v}(\xi_w)\\
&\quad\equiv \sum_{v:V} \delta_{\pi_g(v), \psi} \delta_{\pi_f(w), \phi} \delta_{v, f_V(w,w')} \;g_{\text{lin},v,v'} \circ f_{\text{lin},w,w'}(\xi_w)
\\&\quad= \delta_{\pi_g(f_V(w,w')), \psi} \delta_{\pi_f(w), \phi} \;(g \circ f)_{\text{lin},w,w'}(\xi_w)
\\&\quad= (g \circ f)_{\text{lin},w,w'}(\xi_w)
\\&\quad= \delta_{\pi_{g\circ f}(w), \rho}\;(g \circ f)_{\text{lin},w,w'}(\xi_w)
\\&\quad= \left(  \text{Lin}\,(g\circ f)_{\text{lin},w'} \right)_{w}(\xi_w).
\end{align}
$$

where the third line uses $\delta_{v, f_V(w,w')}$ to collapse the sum, the fourth line uses the witnessing conditions ($\delta_{\pi_f(w), \phi} = 1$ and $\delta_{\pi_g(f_V(w,w')), \psi} = 1$), and the fifth line reinserts $\delta_{\pi_{g\circ f}(w), \rho} = 1$ (also from witnessing) to match the definition of $\text{Lin}\,(g\circ f)_\rho$. $\square$

##### Worked example: Bell pair, measurement, correction, measurement

To see bundles, measurement contexts, and their composition in action, we trace a small but complete protocol through the semantic model — no IR in this subsection, only the mathematics. The pipeline is:

1. Prepare a Bell pair from two qubits initialized to $\ket{0}$.
2. Measure qubit 1.
3. Flip qubit 2 if (and only if) the outcome was $1$.
4. Measure qubit 2.

Throughout, $Q :\equiv \begin{bmatrix}\mathbb{C}\{0,1\} \\ \downarrow \\ *\end{bmatrix}$ denotes the qubit type.

**Stage 1: Bell pair.** Preparation is a purely linear bundle morphism $u : Q \otimes Q \to Q \otimes Q$: the classical part is $\text{id}_*$, and the single fiber map is the unitary $\text{CNOT} \circ (H \otimes \text{id})$. Starting from the term $\ket{00}$ over the unique base point,

$$
u : \ket{00} \mapsto \tfrac{1}{\sqrt{2}}\bigl( \ket{00} + \ket{11} \bigr).
$$

The base is a singleton, so no classical information exists yet; the entire program state is one fiber vector.

**Stage 2: measure qubit 1.** This is the Measurement example above, with qubit 2 carried along as the captured (right) tensor factor. The pre-linearized map is

$$
f: \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix} \otimes Q \to \begin{bmatrix}\mathbb{C}^2 \\ \downarrow \\ *\end{bmatrix} \otimes \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix},
$$

whose classical part sends $(b, *) \mapsto (*, b)$, with identities on fibers (qubit 2's $\mathbb{C}^2$ passes from the right factor into the left factor, which is where surviving quantum data must sit to be re-linearized). As in the Measurement example, $M(f) \equiv \{0,1\}$: two possible worlds. In context $b$, partial linearization gives the bundle morphism

$$
b : M(f) \;\vdash\; m_1 :\equiv \text{Lin}\,f : \begin{bmatrix}\mathbb{C}^2 \otimes \mathbb{C}^2 \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C}^2_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix}
$$

with classical part $* \mapsto b$ and fiber map $\bra{b} \otimes \text{id} : \mathbb{C}^2 \otimes \mathbb{C}^2 \to \mathbb{C}^2$. The codomain is our first genuinely hybrid type: the base records the measurement outcome, and each base point carries qubit 2's Hilbert space as its fiber. Applying $m_1$ to the Bell state:

$$
b : M(f) \;\vdash\; \Bigl( b,\; \tfrac{1}{\sqrt{2}}\ket{b} \Bigr),
$$

i.e. in world $b$ the term sits over base point $b$ with fiber vector $\tfrac{1}{\sqrt{2}}\ket{b}$. The entanglement of the Bell pair has become a correlation between base label and fiber vector. Note that the fiber vector is deliberately _not_ renormalized: its squared norm $\tfrac{1}{2}$ is the Born probability of world $b$.

**Stage 3: conditional flip.** This stage needs no context at all — it is a single, ordinary bundle morphism

$$
c : \begin{bmatrix}\mathbb{C}^2_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix} \to \begin{bmatrix}\mathbb{C}^2_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix}, \qquad c_{\text{cl}} :\equiv \text{id}, \qquad c_{\text{lin},b} :\equiv X^b.
$$

A classically controlled quantum operation is not a special construct in this model; it is simply a bundle morphism whose fiber maps differ from base point to base point. (In IR, this stage would be plain classical control flow — an `scf.if` on the measurement result.) The state becomes

$$
b : M(f) \;\vdash\; \Bigl( b,\; \tfrac{1}{\sqrt{2}}X^b\ket{b} \Bigr) \equiv \Bigl( b,\; \tfrac{1}{\sqrt{2}}\ket{0} \Bigr):
$$

the two worlds still differ in their base label, but now agree in their fiber vector.

**Stage 4: measure qubit 2.** Analogous to stage 2, with the classical bit riding along as spectator; the context is a second outcome $b' : \{0,1\}$, and the resulting morphism family is

$$
b' : \{0,1\} \;\vdash\; m_2 : \begin{bmatrix}\mathbb{C}^2_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix} \to \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}^2\end{bmatrix}
$$

with classical part $b \mapsto (b, b')$ and fiber maps $\bra{b'} : \mathbb{C}^2 \to \mathbb{C}$. Applying it to the stage-3 state yields, in the joint context $(b, b')$, the term over base point $(b, b')$ with fiber scalar

$$
\tfrac{1}{\sqrt{2}}\langle b'|0\rangle = \delta_{b',0}\cdot\tfrac{1}{\sqrt{2}}.
$$

**Discussion.**

- Of the four naive world combinations $(b, b') : M(f) \times M(m_2)$, exactly two carry a nonzero vector: $(0,0)$ and $(1,0)$. This is the possible-pairs phenomenon made concrete: $M(f) \times_{\text{poss}} M(m_2) = \{(0,0), (1,0)\}$ is a proper subset of the naive product, in accordance with the Proposition (possible pairs are exactly the nonzero blocks). The impossible pairs are not an error state; the formalism simply assigns them the zero map, and no execution ever realizes them.
- The squared norms of the surviving worlds are $\tfrac{1}{2}$ each, summing to $1$: the model propagates unnormalized amplitudes world by world, and Born statistics are read off at the end. World $(0,0)$ and world $(1,0)$ each occur with probability $\tfrac{1}{2}$.
- The second measurement is _deterministic_: $b' = 0$ in every possible world. Semantically, the composite pipeline contains only one bit of genuine randomness even though it contains two measurement stages. This is exactly the kind of fact the merging strategy below can expose: after merging the linearization ops, the classical residue of stage 4 is the constant $0$, so a lowering may delete the second measurement entirely and materialize the result as a constant `false`.
- The correction is what makes it deterministic. Dropping stage 3 leaves the possible pairs $\{(0,0), (1,1)\}$ — the perfect correlation of the Bell pair. Stage 3 shifts that correlation from a cross-world relation ("$b'$ equals $b$") into a compile-time fact ("$b'$ equals $0$").
- At no point did we need density matrices or ensembles: the world-indexed family of pure, unnormalized states — i.e. the hypothetical-judgment discipline $\phi : M(f) \vdash \dots$ — carries all the information, including the probabilities.

##### Lowering Strategy

- Likely not all ops can be lowered at the start.
- First possibility: Direct lowering
  - Shave off ops at the boundary and lower those ops.
- Second possibility: Lower to specialized ops within HLEP
  - This is the implemented approach: see "Normal form of `lin` ops" below.
- Non-invertible linear maps:
  - Automatic block encoding (non-deterministic)
  - Synthesized Uncomputation

##### Optimization Strategy

- Merge linearization ops as much as possible, then perform classical optimization

#### Exponential map

The exponential map obtains a unitary operator from a Lie algebra element and a real number.
It is available only for purely quantum types, which we identify via the linearization functor.
In addition, we only support the Lie algebras $\text{u}(2^n)$, so the only allowed types are $\text{Lin}\begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}^n \end{bmatrix}$, or `!prelim_hlep.lin<i<n>>` in IR syntax.
The Lie algebra element is given in the basis of Pauli products:

$$
\text{u}(2^n) = \text{span}\left( \{\sigma_{1} \otimes \dots \otimes \sigma_{n}\}, \quad \sigma_{1},\dots,\sigma_{n} : \{\text{id}, \sigma_{X},\sigma_{Y},\sigma_{Z}\}\right)
$$

Identity factors are allowed (and required to span all of $\text{u}(2^n)$, including single-qubit terms on a multi-qubit register and the all-identity term generating global phase); in the IR syntax below, qubit indices not mentioned in a product term implicitly carry $\text{id}$.

In IR, we write

```mlir
#operator = prelim_hlep.hamiltonian<3, X[0] * Y[2] + 1.5 * Z[1]>
```

for

$$
\text{operator} = \sigma_{X} \otimes \text{id} \otimes \sigma_{Y} + 1.5\; \text{id}\otimes \sigma_{Z}\otimes \text{id} : \text{u}(2^3).
$$

Verification or canonicalization should ensure a proper form.

**IR Realization:**

```mlir
%out_state = prelim_hlep.exp %param hamiltonian<1, X[0] + Y[0]> %in_state :
	(f64, !prelim_hlep.lin<i1>) -> !prelim_hlep.lin<i1>
```

##### Example: Rotation gate

The single-qubit $Z$-rotation is the exponential map instantiated at $n=1$ with Hamiltonian $\tfrac12\sigma_Z$ and parameter $\theta$:

$$
R_Z(\theta) = \exp\left(-i\theta \cdot \tfrac12\sigma_Z\right) = \begin{bmatrix} e^{-i\theta/2} & 0 \\ 0 & e^{i\theta/2}\end{bmatrix}.
$$

$R_X(\theta)$ and $R_Y(\theta)$ arise identically, by swapping the Pauli term in the hamiltonian attribute.

**IR Realization:**

```mlir
%out_qubit = prelim_hlep.exp %theta hamiltonian<1, 0.5 * Z[0]> %in_qubit :
	(f64, !prelim_hlep.lin<i1>) -> !prelim_hlep.lin<i1>
```

##### Example: GZZ gate

The global-$ZZ$ gate is a common entangling primitive on trapped-ion and neutral-atom hardware, defined as the exponential of a sum of pairwise $ZZ$ interactions:

$$
\text{GZZ}(\theta) = \exp\left(-i\theta \sum_{j<k}\sigma_Z^{(j)}\sigma_Z^{(k)}\right).
$$

For two qubits ($n=2$), the Hamiltonian is simply $\sigma_Z^{(0)}\sigma_Z^{(1)}$:

**IR Realization:**

```mlir
%out_pair = prelim_hlep.exp %theta hamiltonian<2, Z[0] * Z[1]> %in_pair :
	(f64, !prelim_hlep.lin<i2>) -> !prelim_hlep.lin<i2>
```

For more than two qubits, the sum over pairs is expressed by summing the corresponding Pauli-product terms in the hamiltonian attribute, following the same syntax as the general example above.

##### Lowering Strategy

One can start by only supporting basic rotation gates.
The problem of unitary synthesis is well-known.

##### Optimization Strategy

- Merge exponentiation of linearly dependent hamiltonians.

#### Base changes

All quantum types constructed by means of linearization are inherently equipped with a basis.
We identify the linearization of `i<n>` types with qubit arrays in the computational Z-basis.

However, we would often like to consider different bases, in particular the X- and Y-bases of (multi-) qubit systems.
To this end we introduce additional _classical_ types `!prelim_hlep.x<n>` and `!prelim_hlep.y<n>`.
The terms of the former type are length-`n` strings of the symbols `+` and `-`, the symbols for the latter are `->` and `<-`.
The classical information content is in both cases identical to `i<n>`, and it is legal for classical programs to include these types, introduce operations on them and lower them (though this may not serve a practical purpose).

The key ingredient to make the types useful is the imposition that their linearizations can be identified via a distinguished isomorphism -- obtained from viewing `!prelim_hlep.lin<i<n>>`, `!prelim_hlep.lin<!prelim_hlep.x<n>>`, and `!prelim_hlep.lin<!prelim_hlep.y<n>>` as the _same vector space_ equipped with different bases.
Between any pair of these three types, the operation

```mlir
%qubit_in_x_basis = prelim_hlep.base_change %qubit_in_z_basis : !prelim_hlep.lin<i1> -> !prelim_hlep.lin<!prelim_hlep.x<1>>
```

encodes this distinguished isomorphism.

In order to create literal values of these types, we provide

```mlir
%xxx = prelim_hlep.constant "++-" : !prelim_hlep.lin<!prelim_hlep.x<3>>
%yyy = prelim_hlep.constant "><>" : !prelim_hlep.lin<!prelim_hlep.y<3>>
```

to define constant values from string attributes.

### Normal form of `lin` ops

The composition theorem above makes it legal to decompose one `prelimhlep.lin` op into a chain of `lin` ops, as long as the chain's classical functions compose to the original one.
We exploit this for lowering: a preparation pass (`--prelim-hlep-normalize-lin`) rewrites every `lin` op into a chain of ops from a small, fixed set of **shapes**, each of which corresponds directly to one gate, one measurement, or one register rewiring.
A backend conversion (e.g. `--prelim-hlep-to-qco`) then only dispatches on the shape and never interprets a body.
The intermediate IR is ordinary PrelimHLEP, so it is verifiable, inspectable, and can be refined incrementally.

A `lin` op announces its shape with the optional `shape` attribute, printed as a bare keyword after the op name:

```mlir
%out = prelimhlep.lin x (%b : i1 from %q : !prelimhlep.lin<i1>) -> (!prelimhlep.lin<i1>) {
  %one = arith.constant true
  %nb = arith.xori %b, %one : i1
  prelimhlep.output (%nb : i1)
}
```

The tag is a _claim_ about the body, and `LinOp`'s verifier checks it: the body stays the ground truth, and a consumer that trusts the tag can still be sure of what the op does.
Bodies are compared against the shape definitions semantically where they consist of classical bit logic (via a symbolic evaluator over the `arith` ops `constant`, `extui`, `trunci`, `shli`/`shrui` by constants, `ori`, `xori`, `andi`), and structurally where they contain `scf.if`.

All shapes except `split` and `join` operate on single qubits, `!prelimhlep.lin<i1>`.
With `q` standing for that type, the shapes are:

| Shape          | Signature                                       | Body                                                                                                                                                                         | Meaning                                        |
| -------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `alloc`        | `() -> (q)`                                     | outputs the constant `false`                                                                                                                                                 | a fresh qubit in $\ket{0}$                     |
| `split`        | `(i<n> from lin<i<n>>) -> (q, ..., q)`          | output $j$ is bit $j$ of the input (least-significant first)                                                                                                                 | register to qubits (no gate)                   |
| `join`         | `(i1 from q, ..., i1 from q) -> (lin<i<n>>)`    | output bit $j$ is input $j$                                                                                                                                                  | qubits to register (no gate)                   |
| `x`            | `(i1 from q) -> (q)`                            | outputs the negated input                                                                                                                                                    | Pauli $X$                                      |
| `measure`      | `(i1 from q) -> (q, i1)`                        | empty; outputs the input and carries it                                                                                                                                      | measurement, keeping the qubit                 |
| `measure_drop` | `(i1 from q) -> (i1)`                           | empty; carries the input                                                                                                                                                     | measurement, discarding the qubit              |
| `hadamard`     | `(i1 from q) -> (lin<x<1>>)` or `lin<y<1>>`     | `scf.if` on the bit yielding the constant `"-"`/`"<-"` if set, `"+"`/`"->"` otherwise; carried                                                                               | $H$ (X basis) or $S H$ (Y basis)               |
| `phase`        | `(i1 from q) -> (q)`                            | `scf.if` on the bit: `prelimhlep.scale` by a `complex.constant` of unit modulus $c$, else pass through                                                                       | $\mathrm{diag}(1, c)$, i.e. $Z$ or $P(\arg c)$ |
| `ctrl`         | `(i1 from q, ..., i1 from q) -> (q, ..., q, q)` | `scf.if` on the `arith.andi` of all control bits: an `x`- or `phase`-shaped `lin` applied to one captured qubit, else pass through; controls output in order, target carried | multi-controlled $X$ or phase                  |

Everything a backend needs beyond the tag (the phase factor, the controlled gate, the target) is exposed through accessors in `LinShapes.h`, so no consumer has to re-match a body.

The normalization pass accepts exactly the fragment it can express in these shapes:

- classical bit logic that never combines two input bits (every output bit is a constant or a possibly negated input bit),
- at most one `scf.if` per body, in one of three forms: a conditional phase (the "phase tag" pattern), a basis-conditional constant (the Hadamard family, see below), or a controlled sub-circuit (a then-branch of already-normalized `lin` ops applied to captured values, passed through in the else-branch),
- classical auxiliary results, which become measurements of the bits they depend on,
- `lin` ops nested directly in a body, which act on the captured factor only and are hoisted out.

Ops are processed innermost first.
By the time an enclosing body is examined, the ops inside its `scf.if` branches are already in normal form, so any sequence of gates can be put under control one gate at a time (a nested `ctrl` simply gains the enclosing controls).
Conditions on bits required to be $0$ are handled by $X$-conjugation of those bits.
Multi-qubit operands are split lazily, only when some bit is touched individually, and outputs that are exactly an untouched operand reuse it, so pure permutations of whole registers leave no op behind.

Bodies outside this fragment (arithmetic mixing input bits, discarding a qubit without measuring it, calls that survived inlining, ...) are reported as errors; general reversible-circuit synthesis and automatic uncomputation are out of scope for now.
Because the pass leaves tagged ops alone, it is idempotent and can be re-run after further transformations.

The gate-level ops that are not linearizations (`prelimhlep.exp`, `prelimhlep.scale`, `prelimhlep.add_phase`, `prelimhlep.base_change`, `prelimhlep.constant`) are not touched by the normalization; they are already at the granularity of the shapes and are lowered directly by the backend conversion.

### Further IR examples

Here we provide examples combining the IR ingredients introduced above.

#### Hadamard Gate

```mlir
func.func @hadamard(%in_qubit: !prelim_hlep.lin<i1>) -> !prelim_hlep.lin<i1> attributes { prelim_hlep.halo } {
  %out_qubit_x_basis = prelim_hlep.lin (
    %in_bit: i1 from %in_qubit: !prelim_hlep.lin<i1>,
  ) -> (!prelim_hlep.lin<!prelim_hlep.x<1>>) {
    %out_bit_x = scf.if %in_bit {
      %plus = prelim_hlep.constant "+" : !prelim_hlep.lin<!prelim_hlep.x<1>>
      scf.yield %plus
    } else {
      %minus = prelim_hlep.constant "-" : !prelim_hlep.lin<!prelim_hlep.x<1>>
      scf.yield %minus
    }
    prelim_hlep.output (%out_bit_x)
  }
  %out_qubit = prelim_hlep.base_change %out_qubit_x_basis : !prelim_hlep.lin<!prelim_hlep.x<1>> -> !prelim_hlep.lin<i1>
  return %out_qubit : !prelim_hlep.lin<i1>
}
```

## Open Questions / TODOs

- **Coproduct/Sum in the IR** (see "Coproduct/Sum" under Type System): do we have explicit ways to deal with this constructor in the IR, or is it only needed at the semantic level?
- **Broad / prior art survey** (see "Existing and proposed high-level languages can be embedded" under Broad): the qurts and silq entries, and the general "From …" bullet, are still unfilled; the qrisp and quipper entries should be treated as the template once these are completed.
- **Dialect namespace**: `prelim_hlep` bakes in "preliminary" as a namespace prefix. This should be revisited (dropped or renamed) once the dialect graduates from draft status, so the placeholder name doesn't leak into a stable API.
