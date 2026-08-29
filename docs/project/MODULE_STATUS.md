# Module Status

| Module | Status | Owner / baseline | Notes |
|---|---|---|---|
| `ChatGPTEnhancer/Sources/Bootstrap` | Active | `CEBootstrap` | Single constructor/startup owner for enhancer. New constructors are prohibited by current architecture. |
| `ChatGPTEnhancer/Sources/Core` | Active / Shared core | `CECore`, `CEConversationContext` | Generic UIKit helpers and sole active conversation context. Shared state owner; conflict-check before parallel edits. |
| `ChatGPTEnhancer/Sources/Network` | Active / Shared core | `CENetworkObserver`, `CEAPIClient` | Observer owns passive host-network observation; API client remains sole enhancer-originated request path. Alpha58 adds user-started sanitized re-entry transport/response structure tracing only. HTTP 429 is terminal for the current enhancer request. Sensitive headers stay memory-only. |
| `ChatGPTEnhancer/Sources/Storage` | Active | `CECatalog` | Conversation ID/title/update-time catalog. |
| `ChatGPTEnhancer/Sources/UI` | Active / Shared surface | `CEEnhancerUI`, `CEConversationUIReloadEvidence` | Host UI integration plus ephemeral Reload proof. Existing nav-replacement / scroll-anchor evidence remains diagnostic completion evidence only; alpha58 does not change UI behavior. |
| `ChatGPTEnhancer/Sources/Export` | Active | `CEMarkdownExporter` | Complete-conversation Markdown export path. |
| `ChatGPTEnhancer/Sources/Features` | Active | Feature-specific modules | Exact-ID Sync/Reload/Rename behavior. Current Sync still performs enhancer GET then existing manual Reload handoff; alpha58 intentionally does not change production behavior. |
| `ChatGPTEnhancer/Sources/Diagnostics` | Active / Experimental | diagnostic/probe modules | Alpha55–57 navigation evidence is retained. Alpha58 compares official completed-conversation re-entry network structure/capture provenance against enhancer actions; diagnostics remain evidence-only and do not mutate navigation or replay requests. |
| `.github/workflows/build-enhancer.yml` | Active | Enhancer CI | Normal enhancer CI/artifact path on `feat/chatgpt-enhancer-v0.1`; isolated recognition trigger was removed after alpha58 candidate build. |
| `GPTWebKit/` native app source | Legacy candidate | legacy branches | Native/utility line retained in repository; not current enhancer baseline. |
| `.github/workflows/build-ipa.yml` | Legacy active-on-branches | legacy IPA CI | Builds older native/WebView app artifacts. |

## Allowed statuses

Use concise statuses such as Active, Candidate, Stable, Frozen, Experimental, Deprecated, or Unknown / Unverified.

## Frozen rule

No product module is currently Frozen/Stable. Do not infer Frozen/Stable merely from age, CI success or Artifact production.

## Current candidate

- Recognition candidate: `0.1.0-alpha58-reentry-network-trace`.
- Validation: **Code written → CI passed → Artifact produced; Runtime/manual pending**.
- Runtime acceptance is diagnostic: compare official entry of an already-finished conversation with Sync/Reload. Do not treat the candidate as proof that raw HTTP replay refreshes the host UI.

## Auto-refresh rule

Update this matrix when modules are added, ownership changes, a module becomes stable/frozen, a frozen decision is reopened, or a new candidate supersedes an old baseline.