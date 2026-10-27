# 18. Database Backup — Scenarios & Labs

> Module 3 operational reference. Full scenarios in the module's
> [SCENARIOS.md](../3-Automated-Database-Backup-with-Timestamp/docs/SCENARIOS.md);
> executable labs in [docs/labs/](../3-Automated-Database-Backup-with-Timestamp/docs/labs/).

---

## Exit-code contract

| Code | Meaning |
| :--: | :--- |
| `0` | Success |
| `1` | Configuration / safety violation |
| `2` | Partial failure (dump, compression, retention) |

## Common scenarios

- **Successful backup** — exit `0`, compressed archive created.
- **Missing password** — exit `1`.
- **System path as backup dir** — exit `1`.
- **Missing dump tool** — exit `1`.
- **Failed dump** — exit `2`, partial file removed.
- **Compression failure** — exit `2`, raw `.sql` retained.
- **Retention pruning** — old archives removed, count reported.
- **Dry run** — exit `0`, nothing touched.

## Labs

- [Lab 1 — Backup & Dry Run](../3-Automated-Database-Backup-with-Timestamp/docs/labs/LAB1_BACKUP_AND_DRY_RUN.md)
- [Lab 2 — Exit Codes & Retention](../3-Automated-Database-Backup-with-Timestamp/docs/labs/LAB2_EXIT_CODES_AND_RETENTION.md)
- [Lab 3 — Scheduling in Production](../3-Automated-Database-Backup-with-Timestamp/docs/labs/LAB3_PRODUCTION_SCHEDULING.md)

## Related

- [16. Overview](16-Database-Backup-Overview.md)
- [17. Bash vs PowerShell](17-Database-Backup-Bash-vs-PowerShell.md)
