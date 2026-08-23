# ChatGPTEnhancer architecture

## Bootstrap

`Sources/Bootstrap/CEBootstrap.mm` is the only constructor entry point. It validates `com.openai.chat`, then starts independent subsystems. New features should not add constructors.

## Core

`CECore` owns generic UIKit helpers and the current conversation context. Feature code should ask `CEConversationContext` for the active conversation instead of independently guessing IDs.

## Network

`CENetworkObserver` passively observes ChatGPT's own Foundation networking and keeps one in-memory request template plus known project IDs. Sensitive auth headers are never persisted.

`CEAPIClient` is the only component allowed to make enhancer-originated ChatGPT requests. It clones the in-memory official request environment, marks its own requests so the observer does not recursively capture them, and centralizes retries/backoff.

## Storage

`CECatalog` maintains the conversation ID/title/update-time map. Long-press resolution uses the catalog instead of hard-coding private Swift model classes. Duplicate titles are returned as multiple candidates and resolved with a native chooser.

## UI

`CEEnhancerUI` owns all host-app surface integration:

- records the most recent touched view,
- appends one `.displayInline` section to a menu that already looks like an official conversation menu,
- owns the draggable `MD` button.

Feature modules do not hook UIKit directly.

## Features

`CEFeatures` currently exposes two capabilities:

- Markdown export
- Conversation rename

Future features should be split into their own files once the first runtime compatibility test passes. Suggested future modules include project batch export, copy conversation link, local backup, attachment utilities, and per-feature settings.

## Compatibility rules

1. Do not hard-code ChatGPT Swift class names unless a future feature has no public-runtime alternative.
2. A failed hook must degrade one feature rather than crash the host app.
3. Do not persist Authorization, cookies, account IDs, or raw request templates.
4. Do not replace official menu items; enhancer actions live in a separate inline section below them.
5. Never load a conversation UI merely to export it; use the conversation ID and complete JSON endpoint.
6. Server `500/502/503/504`, transport failures, and `429` are retryable; mutation/export UI should not expose the first transient failure directly.
