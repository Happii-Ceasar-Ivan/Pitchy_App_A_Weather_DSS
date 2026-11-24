# Safety thresholds (P-12)

`rules.yaml` holds the safety rules, each with its source. `services/safety_engine/rules.py` loads and validates it strictly; a broken file stops the engine instead of guessing.

- **Heat (WBGT):** FIFA Emergency Care Manual (2022), chapter 9. At **32 °C or above**, cooling breaks must be used (after about 30 and 75 minutes), or the match may be postponed or cancelled by the match management team. Below 32 °C there is no FIFA trigger, which does **not** mean "safe".
- **PFF advisory:** shown as a notice for kickoffs between 9 AM and 3 PM Manila time. Its "above 32°" rule is not applied because it doesn't say which measure it means.
- **Lightning and rain:** no approved rule yet (DEC-06, P-11). Pitchy shows official PAGASA alerts instead.
- `status: draft` until the team approves the file (`docs/decisions/safety-rules-files.md`).

To change a rule: edit the value **and** its source, bump `rule_set_version`, then run `uv run pytest tests/test_safety_rules.py`.
