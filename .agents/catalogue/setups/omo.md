---
name: omo
provider: omo-setup
opencodePlugin: oh-my-openagent
summary: >-
  OhMyOpenCode is an OpenCode plugin whose own installation manages its skills.
  This entry explains it and links to the official setup; it does not distribute
  any part of the harness.
prerequisites:
  - OpenCode installed and running
  - npm able to resolve the public oh-my-openagent package
  - A writable personal OpenCode configuration
upstreamLinks:
  - label: oh-my-openagent on npm
    url: https://www.npmjs.com/package/oh-my-openagent
    purpose: inspect-source
  - label: OpenCode
    url: https://opencode.ai/
    purpose: official-setup
attribution:
  distributor: >-
    npm registry (oh-my-openagent), declared by the publisher's OpenCode
    configuration
  authorship:
    _tag: AuthorUnknown
    reason: >-
      The consumed declaration names a package specifier only; no author is
      declared in the inspected source.
  licence:
    _tag: LicenceUnknown
    reason: >-
      No licence text is distributed with this setup record, because no upstream
      content is redistributed here.
---

## Add the plugin to your OpenCode configuration

Register "oh-my-openagent" in the OpenCode plugin list. OpenCode installs plugins
with npm, so npm must be able to resolve the public package.

## Let the plugin manage its own skills

The harness installs and updates its skills itself. Nothing in this library
copies, mirrors or archives them, so there is no download here to install.

## Inspect before you adopt

Read the upstream package and the OpenCode plugin documentation, then confirm the
setup yourself. This entry requests inspection, not automated installation or
provider authentication.
