# Preserve the Dotfiles System Model

`.agents/resources/system-model.md` is the canonical conceptual model for this
repository.

When changing projection, resolution, reconciliation, materialisation,
lifecycle, observation, diagnosis, drift detection, or convergence mechanisms:

- Identify the conceptual responsibility being changed.
- Preserve the system invariants documented in the model.
- Keep source, projection context, desired, live, and observed state distinct.
- Verify changed intent, reapplication, removal, and opt-out behaviour.
- Validate convergence through the affected feature's real interface.
- Update the model when system semantics change.
- Update implementation references, rather than the model, when only a current
  mechanism or operational procedure changes.
