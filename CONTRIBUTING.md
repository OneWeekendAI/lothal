# Contributing to Lothal

Thanks for helping. Lothal is a one-person project, so replies may be slow, but every issue
and pull request gets read.

The roadmap, what is in progress and what is done, is public on
[Kriya](https://kriya.meetdev.in/p/683ae810575172a0f270cd0b970d091e). Check it
before starting something big, in case it is already planned or under way.

## Reporting a bug

Open a [GitHub issue](https://github.com/OneWeekendAI/lothal/issues) and include:

- your OS and version (Windows, macOS or Linux)
- the Lothal version, or the commit if you built from source
- what you did, what you expected, and what happened
- the log, if there is one (Godot writes it under the app's `user://logs/` folder)

## Sending a pull request

- Keep it small and focused on one thing. Adding a real part to `data/parts/` is a great
  first PR; every number needs a `source` saying where it came from.
- Run the test suite before you open the PR. Every check must pass:

  ```bash
  tools/run_tests_safe.sh      # macOS / Linux
  tools/run_tests_safe.ps1     # Windows
  ```

- Say in the description what changed and why.

## Licence of contributions

By submitting a contribution you agree it is licensed under GPL-3.0-or-later, and you grant
Ritwik Singh a perpetual, irrevocable right to also relicense your contribution under other
terms.
