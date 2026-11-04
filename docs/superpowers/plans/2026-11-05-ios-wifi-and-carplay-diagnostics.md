# iOS Wi-Fi and CarPlay Diagnostics Follow-up Plan

## Tasks

1. [x] Add the MOTO-HUB-style manual Wi-Fi fallback and copy-password action to bike review and saved-bike flows.
2. [x] Preserve automatic Wi-Fi setup errors with their iOS domain/code in the shareable diagnostic.
3. [x] Rename and explain the experimental local receiver endpoint check and its failure state.
4. [x] Review the diff and Xcode resource/source references; leave device build verification to Codemagic.

## Constraints

- Keep iOS 16 support and the current bike store/Keychain behavior.
- Do not expose the saved password until the rider taps Copy password.
- Do not change the receiver transport or imply that this probe projects CarPlay to the dashboard.
- Do not add or run tests in this turn.
