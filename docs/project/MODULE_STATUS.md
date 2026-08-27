# Module Status

| Module | Status | Owner / baseline | Notes |
|---|---|---|---|
| `ChatGPTEnhancer/Sources/Bootstrap` | Active | `CEBootstrap` | Single constructor/startup owner for enhancer. New constructors are prohibited by current architecture. |
| `ChatGPTEnhancer/Sources/Core` | Active / Shared core | `CECore`, `CEConversationContext` | Generic UIKit helpers and sole active conversation context. Shared state owner; conflict-check before parallel edits. |
| `ChatGPTEnhancer/Sources/Network` | Active / Shared core | `CENetworkObserver`, `CEAPIClient` | Observer owns passive host-network observation; API client remains sole enhancer-originated request path. HTTP 429 is terminal for the current enhancer request. Sensitive headers stay memory-only. |
| `ChatGPTEnhancer/Sources/Storage` | Active | `CECatalog` | Conversation ID/title/update-time catalog. |
| `ChatGPTEnhancer/Sources/UI` | Active / Shared surface | `CEEnhancerUI`, `CEConversationUIReloadEvidence` | Host UI integration plus ephemeral Reload proof. Alpha57 adds active attached `UINavigationController` object replacement as an evidence-backed UI rebuild signal while retaining scroll/anchor proof. Navigation object identity is in-memory only and never identity authority. |
| `ChatGPTEnhancer/Sources/Export` | Active | `CEMarkdownExporter` | Complete-conversation Markdown export path. |
| `ChatGPTEnhancer/Sources/Features` | Active | Feature-specific modules | Exact-ID Sync/Reload/Rename behavior; alpha52+ keeps truthful completion and one-delivery route suppression. Alpha57 changes only UI rebuild proof, not route/request ownership. |
| `ChatGPTEnhancer/Sources/Diagnostics` | Active / Experimental | diagnostic/probe modules | Alpha55/56 navigation mutation/instance tracing established active nav replacement around the same-current route. Diagnostics remain evidence-only and do not mutate navigation. |
| `.github/workflows/build-enhancer.yml` | Active | Enhancer CI | Normal enhancer CI/artifact path on `feat/chatgpt-enhancer-v0.1`; isolated feature trigger is removed after candidate builds. |
| `GPTWebKit/` native app source | Legacy candidate | legacy branches | Native/utility line retained in repository; not current enhancer baseline. |
| `.github/workflows/build-ipa.yml` | Legacy active-on-branches | legacy IPA CI | Builds older native/WebView app artifacts. |

## Allowed statuses

Use concise statuses such as Active, Candidate, Stable, Frozen, Experimental, Deprecated, or Unknown / Unverified.

## Frozen rule

No product module is currently Frozen/Stable. Do not infer Frozen/Stable merely from age, CI success or Artifact production.

## Current candidate

- Recognition candidate: `0.1.0-alpha57-navigation-rebuild-proof`.
- Validation: **Code written → CI passed → Artifact produced; Runtime/manual pending**.
- Runtime acceptance must confirm the alpha56 false-negative is corrected before any Stable/Frozen claim.

## Auto-refresh rule

Update this matrix when modules are added, ownership changes, a module becomes stable/frozen, a frozen decision is reopened, or a new candidate supersedes an old baseline.