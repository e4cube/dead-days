# Legacy v0.3

The root `main.py` remains the Pygame v0.3 reference and launch entry.
Original source is preserved in Git at commit `33c9d31` (branch `main`).
Do not run old revisions with `--selftest` against a player directory: they can overwrite/delete save.json.
The rebuild branch isolates selftests in TemporaryDirectory, including Markdown exports.
Legacy saves are not migrated or read by Godot.
