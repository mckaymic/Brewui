# Contributing to Brewui

Thanks for your interest in improving Brewui! This document explains how to get set up,
the conventions the project follows, and how to submit changes.

## Code of Conduct

Be respectful and constructive. Assume good intent, keep discussion focused on the work,
and help make this a welcoming project for everyone.

## Getting Started

1. **Fork** the repository and clone your fork.
2. Open `Brewui.xcodeproj` in Xcode 16 or later.
3. Make sure the project builds and runs (**⌘R**) before making changes.
4. Create a feature branch off `main`:
   ```bash
   git checkout -b feature/short-description
   ```

## Project Layout

Brewui uses an MVVM structure. Please place new code accordingly:

- `Brewui/Models/` — plain data types
- `Brewui/Views/` — SwiftUI views (reusable pieces go in `Views/Components/`)
- `Brewui/ViewModels/` — observable view state and logic
- `Brewui/Services/` — Homebrew CLI integration and data access

All interaction with the `brew` CLI should go through `BrewService` / `ProcessRunner`
rather than spawning processes directly from views or view models.

## Coding Guidelines

- **Language:** Swift, SwiftUI, and Swift Concurrency (`async`/`await`, actors).
- **Style:** Match the surrounding code — 4-space indentation, `// MARK:` section markers,
  and descriptive names.
- **Concurrency:** Keep UI updates on the main actor; long-running work belongs in
  services. Follow the existing `actor` patterns in `BrewService` and `FormulaeAPIService`.
- **No new dependencies** without discussion first — Brewui currently has zero third-party
  dependencies, and we'd like to keep the footprint small.
- **Logging:** Use the existing console/output patterns rather than scattering `print`
  statements in new user-facing flows.

## Testing

- Unit tests live in `BrewuiTests/`, UI tests in `BrewuiUITests/`.
- Run tests in Xcode (**⌘U**) or from the command line:
  ```bash
  xcodebuild test -project Brewui.xcodeproj -scheme Brewui -destination 'platform=macOS'
  ```
- Please add or update tests for behavior changes where practical.

## Submitting Changes

1. Keep pull requests focused — one logical change per PR.
2. Write clear commit messages describing **what** changed and **why**.
3. Ensure the project builds cleanly and tests pass.
4. Open a PR against `main` with:
   - A description of the change and the motivation.
   - Screenshots or a short clip for any UI changes.
   - A note on how you tested it.

## Reporting Issues

When filing a bug, please include:

- macOS version and Homebrew version (`brew --version`).
- Steps to reproduce.
- What you expected vs. what happened.
- Relevant output from the in-app command console, if applicable.

For feature requests, describe the problem you're trying to solve, not just the proposed
solution — it helps us find the best fit.

---

Thanks again for contributing! 🍺
