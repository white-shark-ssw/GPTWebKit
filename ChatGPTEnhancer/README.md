# ChatGPTEnhancer 0.1.0-alpha1

Target: official ChatGPT iOS app (`com.openai.chat`), iOS 17.0+, designed for TrollFools / 巨魔注入器 plain dylib injection.

## First features

- Adds a separate inline section below the official conversation long-press menu when the conversation can be resolved.
  - `重命名会话`
  - `导出 Markdown`
- Adds a draggable `MD` floating button while a conversation is active.
- Markdown export fetches the complete conversation JSON without rendering the conversation in a WebView.
- Export follows `current_node -> parent -> root`, so edited/regenerated abandoned branches are not mixed into the file.
- Export starts fetching while the rename dialog is open.
- Retries transient server failures (`500/502/503/504`, transport errors, `429`) with backoff.
- Rename uses the direct conversation PATCH path and keeps the official menu untouched.
- Authorization/account headers are only copied in memory from the official app's own requests and are never persisted to disk.

## Compatibility strategy

This dylib intentionally does not hard-code ChatGPT private Swift class names. It only hooks public UIKit/Foundation entry points and recognizes ChatGPT requests/menu content at runtime. If a future ChatGPT release changes one surface, other features can continue working.

The menu extension only appears when both of these are true:

1. the active context menu looks like a conversation menu (at least two official conversation actions are present), and
2. the pressed row can be matched to a conversation ID/title from the catalog.

This reduces the chance of modifying unrelated menus.

## TrollFools

Inject `ChatGPTEnhancer.dylib` into the App Store ChatGPT app. The included plist is only compatibility metadata for loaders that understand MobileSubstrate-style filters; TrollFools can inject the dylib directly.

If the official app updates, re-inject the dylib if your TrollFools build does not automatically retain injections.

## Known alpha limitations

- The first long-press immediately after a cold launch may not show the enhancer section until ChatGPT has made at least one authenticated backend request and the local conversation catalog has finished its first refresh.
- Duplicate conversation titles are disambiguated with a native chooser before export/rename.
- The floating `MD` button is hidden when a left-edge/back interaction clears the current conversation context. Navigation patterns that do not generate a left-edge/back touch may keep it visible until the next context change; this will be refined from real-device feedback.
- If the official app changes its backend host/path or stops exposing reusable authentication headers to URLSession requests, the network adapter will need a compatibility update.
