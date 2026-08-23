# ChatGPTEnhancer

A modular iOS enhancement project for the official ChatGPT app. The first feature set focuses on user-initiated conversation utilities: Markdown export and conversation rename, with a native iOS UI and version-tolerant capability checks.

## v0.1 goals

- Preserve the official app UI and normal behavior.
- Add a separate extension section to conversation context menus.
- Add `重命名会话` and `导出 Markdown` actions.
- Add an optional in-conversation floating `MD` export shortcut.
- Reuse the signed-in app session at runtime; do not persist authorization secrets.
- Retry transient server errors such as 429/500/502/503/504.
- Keep features modular so future enhancements can live under `Sources/Features`.

## Build

The repository includes a GitHub Actions workflow that builds an arm64 iOS 17+ dynamic library and packages it with the filter plist for sideloaded-device injection tools.

This is an independent personal-use enhancement project and is not affiliated with OpenAI.
