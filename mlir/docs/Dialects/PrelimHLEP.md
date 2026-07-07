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
- We are only concerned with pure functions. A function
  $$
  f: \begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \to \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix}
  $$
  is given by a classical part $f_{\text{cl}}:W\to W'$, together with a $W$-family of linear maps $f_{\text{lin},w}:H_{w}\to H_{f_{\text{cl}}(w)}$.
- Purely classical types $W$ are embedded into this type system as covered by the Zero space, and purely linear types $H$ (i.e. vector spaces) cover the singleton:
  $$
  W \equiv\begin{bmatrix}
  0_{\bullet} \\ \downarrow \\ W
  \end{bmatrix},\qquad H \equiv\begin{bmatrix}
  H \\ \downarrow \\ *
  \end{bmatrix}.
  $$
  However, in order classical types to interact meaningfully with quantum types (e.g. by measurement), they need to be embedded into the quantum context. To this end, they are commonly equipped with an "infinitesimal halo" of linearity, which means they are covered by the tensor unit $\mathbb{C}$:
  $$
  \mathbb{C} \times W \equiv\begin{bmatrix}
  \mathbb{C}_{\bullet} \\ \downarrow \\ W
  \end{bmatrix}.
  $$
  This can be thought of as a classical type, together with a quantum phase.
- Types can be constructed in the following ways:
  - Cartesian product:
    $$
    \begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \times \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \equiv \begin{bmatrix}H_{\bullet} \oplus H'_{\bullet} \\ \downarrow \\ W\times W'\end{bmatrix}, \quad \text{Unit: }\begin{bmatrix}0 \\ \downarrow \\ *\end{bmatrix}
    $$
    This represents independent quantum systems. It will be avoided by our IR.
  - Linear product:$$\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \otimes \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \equiv \begin{bmatrix}H_{\bullet} \otimes  H'_{\bullet} \\ \downarrow \\ W\times W'\end{bmatrix}, \quad \text{Unit: }\begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix}$$This represents the ordinary tensor product on purely linear types, and the cartesian types on _classical types with linear halo_. This product will be used implicitly throughout the IR in quantum context.
  - Coproduct/Sum:$$\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \sqcup \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \equiv \begin{bmatrix}H_{\bullet} \sqcup  H'_{\bullet} \\ \downarrow \\ W \sqcup W'\end{bmatrix}, \quad \text{Unit: }\begin{bmatrix} \emptyset \\ \downarrow \\ \emptyset\end{bmatrix}$$This behaves similar to ordinary sum types.
    **Question:** Do we have explicit ways to deal with this in our IR?
  - Linearization:$$\text{Lin}\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \equiv \begin{bmatrix}\bigoplus_{w:W} H_{w} \\ \downarrow \\ *\end{bmatrix}$$This turns a mixed type into a purely linear type. The operation is idempotent. Crucially, it transforms classical types with linear halo into the vector space whose basis is the classical set, but it destroys classical types without linear halo: $$\text{Lin}\begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ W\end{bmatrix} \equiv \begin{bmatrix}\mathbb{C}W \\ \downarrow \\ *\end{bmatrix}, \qquad \text{Lin}\begin{bmatrix}0_{\bullet} \\ \downarrow \\ W\end{bmatrix} \equiv \begin{bmatrix}0 \\ \downarrow \\ *\end{bmatrix}.$$**IR Realization:** `!prelim_hlep.lin<W>`

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

Crucially, $M(f)$ or its terms are not part of the IR. $M(f)$ encodes the different possible worlds the particular program could end up in after execution. It is still possible to obtain a measurement result as an IR value, but this will appear as a term of $V'$ (or `%out_aux : <D>` in this example). See also the measurement example below.

##### Example: X-gate

We start with

$$
f: \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix} \otimes \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix} \otimes \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix},
$$

$$
f_{\text{cl}} = \text{NOT}: \{0,1\} \to \{0,1\}
$$

with identities on fibers.
We observe that

$$
M(f) \equiv \text{Im}\left( b \mapsto \text{pr}_{*}\left( f_{\text{cl}} (b) \right)  \right).
$$

is a singleton. This tells us that no measurement is necessary to realize the program.
Partial linearization yields a map (omitting the unit tensor factors)

$$
*:M(f) \quad\vdash\quad \text{Lin}f: \begin{bmatrix}\mathbb{C}\{0,1\} \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C}\{0,1\}\\ \downarrow \\ *\end{bmatrix},
$$

with unique fiber given as

$$
(\text{Lin}f_{\text{lin},*})_{w,v} = \delta_{\pi(w),*}\,\delta_{v,\,\text{NOT}(w)}\;\text{id}_{\mathbb{C}}
\qquad (w,v \in \{0,1\}),
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
	prelim_hlep.output (%out_lin)
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
M(f) \equiv \text{Im}\left( b \mapsto \text{pr}_{\{0,1\}}\left( f_{\text{cl}} (b) \right)  \right) = \mathrm{Im}(\text{id}_{\{0,1\}}) = \{0,1\},
$$

exhibiting two possible worlds, which means that one measurement must take place for realization.
For the partially linearized map, we get

$$
b:\{0,1\} \quad\vdash\quad \text{Lin}f: \begin{bmatrix}\mathbb{C}\{0,1\} \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}\end{bmatrix},
$$

where the classical part $\text{Lin}f_{\text{cl}}:* \to \{0,1\}$ is determined by $*  \mapsto b$, and on fibers

$$
(\text{Lin}f_{\text{lin},b})_{w,*} = \delta_{\pi(w),\,b}\,\delta_{*,\,*}\;\text{id}_{\mathbb{C}}
\qquad (w \in \{0,1\}),
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
f_{\text{cl}} = \text{COPY}: \{0,1\} \to \{0,1\}^2
$$

with identities on fibers. We again find $M(f) = *$, implying no measurements are needed.
Upon (partial, but in this case full) linearization, we get a unique linear map on the fibers:

$$
(\text{Lin}f_{\text{lin},*})_{w,v} = \delta_{\pi(w),*}\,\delta_{v,\,(w,w)}\;\text{id}_{\mathbb{C}}
\qquad (w \in \{0,1\},\; v \in \{0,1\}^2),
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
f_{\text{cl}} = : \{0,1\} \to *,
$$

with identity on fibers. We find $M(f) = *$, so no measurement is needed. Partial (here full) linearization yields

$$
*:M(f) \quad\vdash\quad \text{Lin}f: \begin{bmatrix}\mathbb{C}\{0,1\} \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix}\mathbb{C} \\ \downarrow \\ *\end{bmatrix},
$$

with fiber

$$
(\text{Lin}f_{\text{lin},*})_{w,*} = \delta_{\pi(w),*}\,\delta_{*,\,*}\;\text{id}_{\mathbb{C}} = \text{id}_{\mathbb{C}}
\qquad (w \in \{0,1\}).
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

where $H' = \mathbb{C}^2$ is the target qubit. The classical part is forgetting the control (the identity would be an alternative),

$$
f_{\text{cl}} = \text{id} : \{0,1\} \to *,
$$

and the fiber maps branch on the control value:

$$
f_{\text{lin},b} = \begin{cases} U & b = 1 \\ \text{id}_{H'} & b = 0 \end{cases}.
$$

Since $W' = V' = *$, we have $M(f) = *$: no measurement is needed. Partial linearization yields

$$
*:M(f) \quad\vdash\quad \text{Lin}f: \begin{bmatrix}\mathbb{C}\{0,1\} \otimes H' \\ \downarrow \\ *\end{bmatrix} \to \begin{bmatrix} H' \\ \downarrow \\ *\end{bmatrix},
$$

with fiber

$$
(\text{Lin}f_{\text{lin},*})_{w,*} = \delta_{\pi(w),*}\;f_{\text{lin},w} = f_{\text{lin},w}
\qquad (w\in \{0,1\}).
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

##### Consistency: Composition of linearization ops

- Has to be semantically equivalent.
- Demonstrate possible combined worlds project into singular worlds.

Given maps

$$
\begin{bmatrix}H_{\bullet} \\ \downarrow \\ W\end{bmatrix} \otimes \begin{bmatrix}H'_{\bullet} \\ \downarrow \\ W'\end{bmatrix} \xrightarrow{\quad f\quad} \begin{bmatrix}K_{\bullet} \\ \downarrow \\ V\end{bmatrix} \otimes \begin{bmatrix}K'_{\bullet} \\ \downarrow \\ V'\end{bmatrix}\xrightarrow{\quad g\quad} \begin{bmatrix}L_{\bullet} \\ \downarrow \\ X\end{bmatrix} \otimes \begin{bmatrix}L'_{\bullet} \\ \downarrow \\ X'\end{bmatrix},
$$

we need to show that, in some sense,

$$
\text{Lin}\,g \;\circ \text{Lin}\,f \;\approx\;\text{Lin}(g\circ f).
$$

This by itself is not a well-defined equation since the terms are dependent: We are given

$$
\phi:M(f) \;\vdash\; \text{Lin}f,\quad \psi:M(g) \;\vdash\; \text{Lin}\,g,\quad \text{and} \quad \rho:M(g\circ f) \;\vdash\; \text{Lin}(g\circ f).
$$

As such, we can form

$$
(\phi, \psi):M(f) \times M(g) \;\vdash\; \text{Lin}f \circ \text{Lin}\,g.
$$

We would like to relate this pair of measurement results to the single measurement result $\rho:M(g\circ f)$ of the joint linearization. Note that we cannot expect to find a map $M(f) \times M(g) \to M(g \circ f)$: Some values $(\phi,  \psi)$ may be impossible and will never be measured, and conversely a single pair $(\phi,\psi)$ may be compatible with several joint outcomes $\rho$.

We therefore define **possible measurement combinations** existentially: a pair $(\phi, \psi) \in M(f) \times M(g)$ is _possible_ iff there exist classical inputs $w:W$ and $w':W'$ that jointly witness both outcomes, i.e.

$$
\pi_f(w) = \phi \quad\text{and}\quad \pi_g\bigl(f_V(w, w')\bigr) = \psi,
$$

where $f_V := \text{pr}_V \circ f_{\text{cl}} : W \times W' \to V$ is the classical residue produced by $f$ on its left (linearized) factor, and $\pi_f, \pi_g$ are the surjections from $W$ (resp. $V$) onto $M(f)$ (resp. $M(g)$). We write $M(f) \times_{\text{poss}} M(g)$ for the set of possible pairs.

TODO: This should be a theorem: Equivalently, $(\phi,\psi)$ is possible iff $\text{Lin}\,g_\psi \circ \text{Lin}\,f_\phi \not\equiv 0$.

We define a **relation**

$$
(\phi,\psi) \sim \rho \quad\iff\quad \exists\, w:W,\, w':W':\; \pi_f(w)=\phi \;\land\; \pi_g\bigl(f_V(w,w')\bigr)=\psi \;\land\; \pi_{g\circ f}(w)=\rho,
$$

where $\pi_{g\circ f}: W \to M(g\circ f)$ is the surjection for the composite (note: a function of $w$ only, since $M(g\circ f) \equiv \text{Im}\bigl(w \mapsto (w' \mapsto \text{pr}_{X'}((g\circ f)_{\text{cl}}(w, w')))\bigr)$). In words: $(\phi,\psi) \sim \rho$ iff some classical input $w$ (with some $w'$) simultaneously witnesses $\phi$ for $f$, $\psi$ for $g$, and $\rho$ for $g\circ f$.
We say that the pair $(w, w')$ _witnesses_ the compatibility $(\phi,\psi) \sim \rho$.

**The relation $\sim$ is surjective onto $M(g\circ f)$.** For any $\rho \in M(g\circ f)$, surjectivity of $\pi_{g\circ f}: W \to M(g\circ f)$ yields $w:W$ with $\pi_{g\circ f}(w)=\rho$; picking any $w':W'$ and setting $\phi := \pi_f(w)$, $\psi := \pi_g(f_V(w,w'))$ gives $(\phi,\psi) \sim \rho$. $\square$

Note that $\sim$ need not be functional: the same pair $(\phi,\psi)$ may relate to distinct $\rho$'s, because the $\psi$-measurement cannot distinguish classical residues that the joint measurement distinguishes. We therefore cannot expect equality of morphisms $\text{Lin}\,g_{\psi} \circ \text{Lin}\,f_{\phi} = \text{Lin}(g\circ f)_{\rho}$ to hold in general. Instead, we evaluate on basis vectors compatible with the measurement results.

**Composition Theorem.** Let $(\phi,\psi) \sim \rho$ be witnessed by $(w, w')$, i.e., $\pi_f(w) = \phi$, $\pi_g(f_V(w, w')) = \psi$, and $\pi_{g\circ f}(w) = \rho$. Then for any vector $\psi_w \in H_w \otimes H'_{w'}$ (a vector in the $w$-summand of the domain at base $w'$):

$$
(\phi,\psi) \sim \rho \text{ witnessed by } (w,w') \quad\vdash\quad \text{Lin}\,g_{\psi} \circ \text{Lin}\,f_{\phi}(\psi_w) \;=\; \text{Lin}(g\circ f)_{\rho}(\psi_w).
$$

By linearity, the maps agree on the subspace spanned by all compatible summands $H_w \otimes H'_{w'}$ (over all $(w,w')$ witnessing $(\phi,\psi)\sim\rho$). When $\sim$ is functional and the witnesses cover all of $W \times W'$, this subspace is the entire domain and we obtain equality of morphisms.

**Proof.** On the base space, the classical part of $\text{Lin}\,g_\psi \circ \text{Lin}\,f_\phi$ at $w'$ is $\iota_g(\psi) \circ \iota_f(\phi)(w')$. Since $\pi_f(w) = \phi$, we have $\iota_f(\phi)(w') = \text{pr}_{V'}(f_{\text{cl}}(w,w'))$. Since $\pi_g(f_V(w,w')) = \psi$, we may take $v = f_V(w,w')$ in the definition of $\iota_g(\psi)$, giving $\iota_g(\psi)(\text{pr}_{V'}(f_{\text{cl}}(w,w'))) = \text{pr}_{X'}(g_{\text{cl}}(f_V(w,w'), \text{pr}_{V'}(f_{\text{cl}}(w,w')))) = \text{pr}_{X'}((g \circ f)_{\text{cl}}(w,w'))$. Since $\pi_{g\circ f}(w) = \rho$, this equals $\iota_{g\circ f}(\rho)(w') = \text{Lin}(g \circ f)_{\rho,\text{cl}}(w')$.
TODO: change this into a multi-line equality chain like the one below.

In fibers, we evaluate on $\psi_w \in H_w \otimes H'_{w'}$. (Introducing $\tilde{\phi} = f_V(w, w') = \text{pr}_V(f_{\text{cl}}(w,w'))$ and abusing notation $\phi = \text{Lin}\,f_{\phi,\text{cl}} : W' \to V'$.)

$$
\begin{align}
&\left(  \text{Lin}g_{\text{lin},\tilde{\phi}} \circ \text{Lin}f_{\text{lin},w'}  \right)_{w}(\psi_w)
= \sum_{v:V}\left(  \text{Lin}g_{\text{lin},\tilde{\phi}} \right)_{v} \circ \left(\text{Lin}f_{\text{lin},w'}  \right)_{w,v}(\psi_w)\\
&\quad\equiv \sum_{v:V} \delta_{\pi_g(v), \psi} \delta_{\pi_f(w), \phi} \delta_{v, f_V(w,w')} \;g_{\text{lin},v,\tilde{\phi}} \circ f_{\text{lin},w,w'}(\psi_w)
\\&\quad= \delta_{\pi_g(f_V(w,w')), \psi} \delta_{\pi_f(w), \phi} \;(g \circ f)_{\text{lin},w,w'}(\psi_w)
\\&\quad= (g \circ f)_{\text{lin},w,w'}(\psi_w)
\\&\quad= \delta_{\pi_{g\circ f}(w), \rho}\;(g \circ f)_{\text{lin},w,w'}(\psi_w)
\\&\quad= \left(  \text{Lin}(g\circ f)_{\text{lin},w'} \right)_{w}(\psi_w).
\end{align}
$$

where the third line uses $\delta_{v, f_V(w,w')}$ to collapse the sum, the fourth line uses the witnessing conditions ($\delta_{\pi_f(w), \phi} = 1$ and $\delta_{\pi_g(f_V(w,w')), \psi} = 1$), and the fifth line reinserts $\delta_{\pi_{g\circ f}(w), \rho} = 1$ (also from witnessing) to match the definition of $\text{Lin}(g\circ f)_\rho$. $\square$

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
In addition, we only support the Lie algebras $\text{u}(2^n)$, so the only allowed types are $\text{Lin}\begin{bmatrix}\mathbb{C}_{\bullet} \\ \downarrow \\ \{0,1\}^n \end{bmatrix}$, or `i<n>` in IR syntax.
The Lie algebra element is given in the basis of Pauli products:

$$
\text{u}(2^n) = \text{span}\left( \{\sigma_{1} \otimes \dots \otimes \sigma_{n}\}, \quad \sigma_{1},\dots,\sigma_{n}\in \{\sigma_{X},\sigma_{Y},\sigma_{Z}\}\right)
$$

In IR, we write

```mlir
#operator = prelim_hlep.hamiltonian<3, X[0] * Y[2] + 1.5 * Z[1]>
```

for

$$
\text{operator} = \sigma_{X} \otimes \text{id} \otimes \sigma_{Y} + 1.5\; \text{id}\otimes \sigma_{Z}\otimes \text{id} \in \text{u}(2^3).
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
