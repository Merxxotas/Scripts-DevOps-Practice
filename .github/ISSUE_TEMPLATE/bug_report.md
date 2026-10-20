---
name: Bug report
about: Something in a module does not behave as documented
title: "[Bug] <module> — <short description>"
labels: bug
assignees: ''
---

<!--
Thanks for taking the time to report this.
Please do NOT use this form for security vulnerabilities — see SECURITY.md for private reporting.
-->

### Module

<!-- Which numbered module? e.g. "2 — Log Cleanup". Use "repository root" for docs or CI issues. -->

### Environment

| Detail | Value |
| :--- | :--- |
| Operating system | <!-- e.g. Ubuntu 24.04, macOS 14, Windows Server 2022 --> |
| Shell / runtime version | <!-- `bash --version`, `$PSVersionTable.PSVersion`, `python3 --version`, `go version` --> |
| Repository commit | <!-- `git rev-parse --short HEAD` --> |

### What happened

<!-- What you observed. Include the exact output. -->

### What you expected

<!-- What the documentation says should happen, and where it says so (file/line is ideal). -->

### Reproduction

<!-- Minimal, exact steps. A copy-pasteable command block is ideal. -->

```bash
# exact commands, with any setup needed
```

### Exit code

<!-- `echo $?` — these modules use a documented exit-code contract: 0 success, 1 configuration or
     safety violation, 2 partial failure. -->

```

```

### Audit log

<!-- If the module wrote one, paste the relevant lines. They show what it actually did. -->

```

```

### Additional context

<!-- Screenshots, verbose output, anything else that helps. -->

<!--
Checklist before submitting:
- [ ] I searched existing issues for this one.
- [ ] I checked the module's README.md and SPECS.md.
- [ ] I removed any credentials, tokens or private hostnames from the text above.
-->
