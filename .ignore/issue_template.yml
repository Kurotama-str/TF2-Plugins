name: Bug or Balance Issue
description: Report a bug or balance issue related to the plugin(s)
title: "[Issue]: "
labels:
  - bug
  - balance issue
body:
  - type: dropdown
    id: issue_type
    attributes:
      label: Issue type
      description: What kind of issue is this?
      options:
        - Bug
        - Balance issue
    validations:
      required: true

  - type: input
    id: server_used
    attributes:
      label: Server used
      description: e.g., Windows SRCDS, Linux SRCDS, game host name, etc.
      placeholder: "Linux SRCDS on Ubuntu 22.04"
    validations:
      required: true

  - type: input
    id: map_played
    attributes:
      label: Map played on
      placeholder: "mvm_bigrock, pl_badwater"
    validations:
      required: true

  - type: textarea
    id: plugins
    attributes:
      label: Plugin(s) related to the issue
      description: List the plugin(s) involved (name and version if possible).
      placeholder: |
        - Hyper Upgrades v0.B1
        - TF2Attributes v1.7.5
        - Custom Attributes (commit abc123)
    validations:
      required: true

  - type: textarea
    id: what_happened
    attributes:
      label: What is the issue?
      description: What happened? What did you expect to happen?
      placeholder: |
        Describe the problem and the expected behavior.
        Include any errors shown in the game console or server logs.
    validations:
      required: true

  - type: textarea
    id: suspected_cause
    attributes:
      label: What seems to cause the issue?
      description: If you have an idea, explain what might be causing it (specific actions, conditions, steps).
      placeholder: |
        Example:
        - Happens after changing class to Spy
        - Only on MvM maps
        - After buying "Fire Resistance" upgrade
    validations:
      required: false

  - type: dropdown
    id: urgency
    attributes:
      label: Urgency
      description: How urgent do you think fixing this is?
      options:
        - Low – minor inconvenience
        - Medium – impacts gameplay but not game-breaking
        - High – game-breaking or server-crashing
    validations:
      required: true

  - type: textarea
    id: additional_info
    attributes:
      label: Additional information
      description: Add any extra details that may help (screenshots, logs, config snippets).
      placeholder: |
        - Relevant log excerpts
        - Steps to reproduce
        - Config files (hu_upgrades.cfg, hu_attributes.cfg, etc.)
    validations:
      required: false
