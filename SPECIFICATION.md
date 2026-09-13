# पेंड Point — Development Specification

This document records binding constraints for any future work (by Claude Code or
any contributor) on this project, on top of the functional Software Requirements
Specification referenced in [README.md](README.md).

## Development Constraints

The app's configuration, dependency versions, and architecture are confirmed
working and stable. Going forward:

1. **No version changes.** Do not upgrade, downgrade, or otherwise modify
   dependency, SDK, Gradle, Flutter/Dart, or plugin versions — including
   `pubspec.yaml`, `pubspec.lock`, `android/build.gradle*`,
   `android/gradle/wrapper/gradle-wrapper.properties`, `ios/Podfile`, and any
   CI/toolchain version pins — unless explicitly requested.

2. **No architectural changes.** Follow the existing code patterns and
   conventions already present in the codebase (state management approach,
   folder/module structure, navigation, data layer abstractions, naming, etc.).
   Do not introduce new architectural patterns or restructure existing ones.

3. **No deprecated API usage.** Avoid deprecated methods/APIs in any new or
   modified code — across the Flutter/Dart SDK, Android/iOS platform APIs, and
   third-party packages already in use. If existing code being touched relies
   on a deprecated API, flag it rather than silently changing/upgrading it
   outside the scope of the requested task.

4. **Scoped changes only.** Make only the specific changes requested, matching
   the existing style and conventions of the surrounding code.

**Why:** the app was brought to a working, correctly configured state after
prior fixes (see git history: `fixed agsin`, `some fixes`, `fix most of the
issue`, `fix issues`). These constraints exist to prevent regressions from
unrelated version bumps, architectural churn, or deprecated-API changes.
