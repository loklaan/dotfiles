# Dotfiles System Model

This repository is an executable desired-state model for a user environment.
It does more than store files. It describes what should exist on a machine, how
that intent varies between machines, and how to determine whether the live
environment matches it.

This is a **resource, not a rule**. It defines the concepts and system
properties that should survive changes to the underlying tools. The current
tools are one realisation of the model, not the model itself.

## System outcome

Given a supported machine and its local context, the system should converge on
the intended user environment. Reapplying the same intent should be safe. A
human should be able to tell whether convergence succeeded and, when it did
not, what prevented it.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../../support/diagram-system-model-dark.svg">
    <img src="../../support/diagram-system-model-light.svg" alt="dotfiles system model" width="1400">
  </picture>
</p>

## State domains

The system works across several kinds of state. Keeping them distinct avoids
ambiguous terms such as "runtime state."

### Source model

The portable, version-controlled expression of intent. It contains managed
content and instructions for deriving machine-specific desired state.

The source model is not a literal copy of the home directory. A source entry
may carry instructions about its target path, permissions, rendering,
inclusion, or lifecycle.

### Projection context

Facts and choices used to resolve the source model for one machine. Examples
include operating system, architecture, hostname, machine role, user opt-ins,
and the availability of credentials or external tools.

Context selects a variation of the same model. It should not require separate
copies of the model for every machine type.

### Resolved desired state

The concrete state intended for one machine after evaluating the source model
against its projection context. Conditions and templates have been resolved at
this point.

### Live state

The files, permissions, packages, services, caches, and other operational state
that currently exist on the machine. Live state may differ from desired state.

### Observed state

A measured view of live state. Observers turn raw machine state into useful
claims such as healthy, missing, stale, disabled, or invalid.

## Core operations

### Projection

Projection is the overall process that interprets the portable source model
for one machine and realises that intent in its live environment.

Projection includes resolution and reconciliation. It is broader than copying
files.

Observation and diagnosis sit outside projection. They close the control loop
by determining whether reconciliation succeeded or should run again.

### Resolution

Resolution evaluates source instructions against projection context to produce
resolved desired state. It decides questions such as:

- Which configuration applies to this machine?
- What concrete value should a template contain?
- Should an optional component exist here?
- Which external artifact should be acquired?

Resolution computes intent. It should not depend on accidental live state
unless that state is an explicit input to the model.

### Reconciliation

Reconciliation compares desired state with live state and performs the changes
needed to align them. Depending on the resource, this may create, update,
remove, enable, disable, start, or stop something.

Reconciliation is stronger than installation. Installation usually describes
an initial transition; reconciliation must also handle reapplication, changed
intent, and opt-out.

### Materialisation

Materialisation is the part of reconciliation that creates concrete files,
directories, links, content, and permissions from resolved desired state.

### Observation

Observation inspects live state without changing it. It supplies evidence about
health and drift rather than assuming that a successful command produced the
intended outcome.

### Diagnosis

Diagnosis explains an observed failure or divergence in actionable terms. A
useful diagnosis identifies the failing boundary and the next corrective
action; it does not only report that the system is unhealthy.

### Convergence

Convergence is the property that reconciliation moves live state toward desired
state and becomes stable once they agree. Repeated application with unchanged
inputs should produce no meaningful changes.

### Drift

Drift is a meaningful difference between desired and observed state. It can
include changed files, outdated tools, stale private caches, incorrect service
state, or a source checkout behind its expected revision.

Not every unmanaged difference is drift. The model must first claim ownership
of the state being compared.

## Architectural primitives

Features are composed from a smaller set of reusable primitives:

- **Managed resource** — a unit of state the model owns, such as a file,
  package, service, or cache entry.
- **Projection directive** — metadata that controls how a source entry maps to
  desired state, such as its target path, permissions, or rendering behaviour.
- **Template** — an expression that derives content or structure from
  projection context.
- **Conditional** — an explicit rule deciding whether a resource belongs in a
  machine's desired state.
- **External input** — content or data acquired from outside the repository,
  such as an archive, package, release, or secret.
- **Lifecycle effect** — an ordered imperative action used to reconcile state
  that cannot be represented as files alone.
- **Observer** — a read-only check that measures one part of live state.
- **Policy** — a constraint on how projection or reconciliation may operate,
  especially around security, ownership, and failure handling.

These are conceptual primitives. Chezmoi attributes, Go templates, mise tasks,
and shell scripts are mechanisms that currently implement them.

## Declarative and imperative boundaries

The source model should express desired state declaratively wherever practical:
describe the outcome, then let the projection engine determine the required
file change.

Lifecycle effects are appropriate when the target is operational rather than
file-shaped. Examples include enabling a service, refreshing a tool cache, or
reloading a process after configuration changes.

An imperative effect should still reconcile toward an explicit outcome. It
should be ordered, safe to repeat, and bounded to the resource it owns. It must
not become a hidden second source of truth.

## System invariants

Any implementation of this model must preserve these properties:

1. **Managed intent is explicit.** The source model identifies the state it
   owns; unrelated live state is left alone.
2. **Intent and context are separate.** Machine facts and user choices vary the
   model without requiring divergent copies of it.
3. **Variation is resolved deliberately.** Platform and machine differences
   are visible conditions, not accidental behaviour.
4. **Reapplication is safe.** Repeating reconciliation with unchanged inputs is
   stable and does not compound side effects.
5. **Opt-out is real.** Removing a resource from desired state removes,
   disables, or stops the managed live state where appropriate.
6. **Imperative effects remain convergent.** Scripts and hooks reconcile an
   outcome rather than blindly repeating mutations.
7. **Sensitive inputs remain external.** Secrets are not committed to the
   source model or exposed through unsafe process arguments or logs.
8. **Optional inputs degrade safely or fail clearly.** Missing optional tools,
   credentials, or network access either degrade safely or produce an
   actionable failure; they do not create ambiguous partial state.
9. **Convergence is observable.** Health and drift are checked through the live
   system's real interfaces, not inferred only from source files or command
   exit codes.
10. **Bootstrap and update preserve the same model.** Fresh, interactive,
    non-interactive, local, and fleet paths resolve the same intent for the same
    context.

## Composition into features

A feature is a user-facing outcome assembled from concepts and primitives.

For example, an optional Linux daemon is not one primitive. It combines:

1. A user choice in projection context.
2. A conditional that includes the package and configuration on Linux when
   enabled.
3. Materialisation of its service definition.
4. Lifecycle effects that start it on opt-in and stop it on opt-out.
5. An observer that reports whether the service reached its desired state.

Describing features this way separates the outcome from the tools currently
used to achieve it.

## Current realisation

The repository currently maps the model to mechanisms as follows:

| Concept | Current mechanism |
|---|---|
| Source model | Chezmoi source state under `home/` |
| Projection directives | Chezmoi source-state attributes and special filenames |
| Projection context | Chezmoi data, prompts, built-in machine facts, and availability of external tools and credentials |
| Resolution | Go templates and shared template fragments |
| Materialisation | Chezmoi target rendering, file creation, and permission application |
| File reconciliation | `chezmoi apply` |
| Lifecycle effects | Chezmoi hooks and ordered `run_`, `run_once_`, and `run_onchange_` scripts |
| External acquisition | Chezmoi externals, mise, package managers, and guarded secret retrieval |
| Observation and diagnosis | `df-setup`, drift checks, health probes, and end-to-end validation |
| Cross-machine convergence | Bootstrap, update tasks, fleet fan-out, and boot-time application |

This table may change when mechanisms are replaced. The concepts and invariants
above are the compatibility boundary.

## Evaluating a mechanism change

Before replacing a projection engine, package manager, secret provider,
lifecycle mechanism, or observer, answer these questions:

1. Which conceptual responsibility does the current mechanism implement?
2. Can the replacement represent the same inputs and resolved desired state?
3. Does it reconcile changed intent, including removal and opt-out?
4. Is repeated execution stable?
5. Does it preserve security and ownership policies?
6. Can convergence and drift still be observed through real system behaviour?
7. Do fresh install, update, and fleet paths retain equivalent semantics?
8. What migration is required for live state owned by the old mechanism?

A mechanism is replaceable when these answers preserve the system model, not
merely when the new tool can produce similar files once.
