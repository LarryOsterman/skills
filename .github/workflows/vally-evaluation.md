---
name: Vally Evaluation
on:
  pull_request:
    paths:
      - tests/scenarios/**/vally/**
      - .github/workflows/vally-evaluation.yml
      - .github/workflows/vally-evaluation.md
  push:
    branches: [main]
    paths:
      - tests/scenarios/**/vally/**
      - .github/workflows/vally-evaluation.yml
      - .github/workflows/vally-evaluation.md
  workflow_dispatch:
    inputs:
      eval_spec:
        description: Optional path to a specific eval spec file (for example tests/scenarios/azure-storage-blob-rust/vally/eval.yaml)
        required: false
        type: string
permissions:
  contents: read
  pull-requests: read
strict: true
network:
  allowed:
    - defaults
tools:
  github:
    mode: gh-proxy
    toolsets: [repos, pull_requests]
  bash:
    [
      git,
      find,
      grep,
      sed,
      sort,
      mktemp,
      cat,
      echo,
      pwd,
      npm,
      node,
      vally,
      copilot,
      mkdir,
      test,
      wc,
      head,
    ]
safe-outputs:
  noop:
---

# Vally Evaluation (Agentic)

Run Vally lint + eval over affected `tests/scenarios/**/vally/**` eval specs.

## Execution Policy

1. Keep the run deterministic and non-interactive.
2. Use strict shell mode (`set -euo pipefail`) for scripts.
3. Use `COPILOT_GITHUB_TOKEN` for Copilot auth when available.
4. If no eval specs are resolved, emit a `noop` safe-output with a short explanation and exit successfully.
5. If specs are resolved, lint first and then run eval.

## Steps

1. Checkout repository with full history (`fetch-depth: 0`).
2. Install Node.js 24.
3. Install tools:
   - `npm install -g @microsoft/vally-cli@0.6.0`
   - `npm install -g @github/copilot`
4. Verify tools:
   - `vally --version`
   - `copilot --version`

5. Resolve eval specs using this logic: for `workflow_dispatch`, use `eval_spec` when provided, otherwise include all `*/vally/eval.yaml|eval.yml` under `tests/scenarios` excluding `tests/scenarios/_shared`; for `pull_request`, diff `${{ github.event.pull_request.base.sha }}` to `${{ github.event.pull_request.head.sha }}` and collect affected scenario vally dirs; for `push`, diff `${{ github.event.before }}` to `${{ github.event.after }}` and if `before` is empty/all-zero include all specs; if any file under `tests/scenarios/_shared/vally/` changed, include all scenario eval specs (excluding `_shared`).

6. Build shared grader plugin:
   - Directory: `tests/scenarios/_shared/vally/grader-plugins/rust-cargo-build-failure`
   - Commands: `npm install` and `npm run build`

7. Lint each resolved spec:
   - `vally lint --eval-spec <spec> --grader-plugin <plugin-dir> --strict`

8. Run eval for all resolved specs:
   - `vally eval -e <spec1> -e <spec2> ... --grader-plugin <plugin-dir> --junit --output-dir vally-results --workers 2`

9. Upload `vally-results` artifacts if present.

## Output Expectations

- Include in summary:
  - number of resolved specs
  - list of resolved specs
  - whether lint and eval completed
- On no-op path, output a clear message that no relevant specs were detected.

## Notes

- Prefer `COPILOT_GITHUB_TOKEN` if provided; otherwise allow fallback token behavior used by Copilot CLI.
- Do not create pull requests or issues in this workflow.
