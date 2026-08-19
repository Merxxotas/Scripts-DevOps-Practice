# Code Style & Engineering Standards 📐

---

## 🌍 Language & Communication
- **English Only**: All code identifiers, comments, logs, documentation, and commit messages must be in English.
- **B2 Level English**: Simple, precise, and universally readable. Avoid overly convoluted wording.

---

## 💬 Commenting Strategy
- **Explain the "Why", Not the "What"**: Clean code expresses *what* it does. Comments explain non-obvious engineering decisions, OS quirks, or workarounds.
- **Zero Dead Code**: Never leave commented-out code blocks or orphan debugging statements in production branches.

---

## 🌿 Branching & Git Workflow
- Direct commits to `main` are prohibited.
- Features and fixes are developed in dedicated branches:
  - `feat/<feature-name>`
  - `fix/<bug-name>`
  - `docs/<docs-name>`
- Conventional Commit standard is enforced: `<type>(<scope>): <description>`.
- All GitHub Actions CI checks must pass before merging into `main`.

