# Workspace Guidelines & Rules

## Automated Testing & Regression Prevention
- **Mandatory Regression Tests**: Whenever making fixes or adding new features to `TextParser.swift` or any core logic, you MUST run the automated regression test suite using `./build.sh` or by executing `swiftc source/TextParser.swift tests/RegressionTests.swift -o /tmp/test && /tmp/test`.
- **Add Tests for New Features**: When introducing new parsing patterns, typo fixes, or edge case handling, add matching assertions to [RegressionTests.swift](file:///Users/suddharay/Library/Mobile%20Documents/com~apple~CloudDocs/Mac%20Projects/Add%20to%20Reminders%20%28Swift%29/tests/RegressionTests.swift).
- **Never Ignore Test Failures**: Every build step must achieve 100% pass rate before completing a task.
