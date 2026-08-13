# EventOps - Code Style & Best Practices

This document outlines the coding standards and conventions for the EventOps project. All contributions and new code must strictly follow these rules to maintain a clean, professional, and production-ready codebase.

## 1. Language & Communication
- **English Only:** All code, variables, functions, comments, and commit messages must be written in English.
- **B2 Level English:** Keep the language clear, simple, and direct. Avoid overly complex idioms or advanced vocabulary. The goal is global readability.
- **Naming Conventions:**
  - Variables & Functions: `snake_case` (e.g., `parse_config_file`)
  - Classes: `PascalCase` (e.g., `WebhookServer`)
  - Constants: `UPPER_SNAKE_CASE` (e.g., `MAX_RETRY_ATTEMPTS`)

## 2. Debugging & Observability (Always Debuggable)
- **Centralized Logging:** Never use `print()` statements in production code. Always use the Python `logging` module.
- **Log Levels:**
  - `DEBUG`: Detailed information for troubleshooting.
  - `INFO`: Normal application behavior (e.g., "Server started on port 8080").
  - `WARNING`: Something unexpected happened, but the app is still running.
  - `ERROR`: A critical failure that requires attention (e.g., "Failed to execute script").
- **Error Handling:** Use `try/except` blocks defensively. Always catch specific exceptions (e.g., `except FileNotFoundError:`) rather than a broad `except Exception:`.

## 3. Commenting Strategy
- **Technical & Concise:** Comments must be brief, precise, and technical. Avoid verbose storytelling.
- **Focus on the "Why":** Good code explains *what* it does. Comments should explain *why* it was done a certain way (e.g., explaining a workaround or a specific architectural choice).
- **No Stale Comments:** Remove commented-out code before pushing to production. Do not leave "TODO" notes in the main branch unless tied to an active issue tracker.
- **Docstrings:** Use standard docstrings for all classes and major functions to describe inputs and outputs clearly.

## 4. Formatting & Code Structure
- **Formatting:** Code must be consistently formatted. Use standard Python PEP-8 guidelines.
- **Line Length:** Keep lines under 100 characters to ensure readability on standard screens.
- **Production-Ready Structure:**
  - Keep files small and focused on a single responsibility.
  - Separate triggers (e.g., `webhook_server.py`) from core logic (e.g., `rule_engine.py`).
  - Keep configuration parsing isolated from execution logic.

## 5. CI/CD Pipeline Enforcement
- **Automated Validation:** All code pushed to GitHub must pass our **GitHub Actions CI/CD pipeline**. 
- **Linting:** The pipeline enforces formatting rules automatically. If your code does not pass the linter, the build will fail.
- **Testing Requirements:** Any new features must include appropriate tests. The CI pipeline will run these tests across Ubuntu, macOS, and Windows to ensure cross-platform compatibility before code can be merged into `main`.

## 6. Example of Good Code Style

```python
import logging
import subprocess

logger = logging.getLogger(__name__)

def execute_shell_action(action_command: str) -> bool:
    """
    Executes a shell command asynchronously.
    Returns True if execution started successfully, False otherwise.
    """
    try:
        # Use shell=True to allow complex bash commands, but capture output to prevent terminal spam
        process = subprocess.run(
            action_command,
            shell=True,
            capture_output=True,
            text=True
        )
        
        if process.returncode != 0:
            logger.error(f"Action failed with exit code {process.returncode}: {process.stderr}")
            return False
            
        logger.info(f"Action executed successfully: {action_command}")
        return True
        
    except subprocess.SubprocessError as e:
        logger.error(f"Subprocess error during action execution: {e}")
        return False
```
