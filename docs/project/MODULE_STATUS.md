# Module Status

| Module | Status | Owner / baseline | Notes |
|---|---|---|---|
| `ChatGPTEnhancer/Sources/Bootstrap` | Active | `CEBootstrap` | Single constructor/startup owner for enhancer. New constructors are prohibited by current architecture. |
| `ChatGPTEnhancer/Sources/Core` | Active / Shared core | `CECore`, `CEConversationContext` | Generic UIKit helpers and active conversation context. Shared state owner; conflict-check before parallel edits. |
| `ChatGPTEnhancer/Sources/Network` | Active / Shared core | `CENetworkObserver`, `CEAPIClient` | Observer owns official request template/events and the existing NSURLSession hook surface. Alpha54 real-device evidence showed the relevant semantic init/prepare/detail requests do not traverse the specifically instrumented Objective-C task-creation selectors; do not keep expanding diagnostics at those same selectors. API client remains sole enhancer-originated request path. Sensitive headers stay memory-only. |
| `ChatGPTEnhancer/Sources/Storage` | Active | `CECatalog` | Conversation ID/title/update-time catalog and title resolution. |
| `ChatGPTEnhancer/Sources/UI` | Active / Shared surface | `CEEnhancerUI` | Owns host-app UI integration. Feature modules should not create independent UIKit hook ownership. |
| `ChatGPTEnhancer/Sources/Export` | Active | `CEMarkdownExporter` | Complete-conversation Markdown export path. |
| `ChatGPTEnhancer/Sources/Features` | Active | Feature-specific modules | Exact-ID Sync/Reload/Rename behavior; alpha52+ retains request+UI completion semantics and delivery-aware route suppression. |
| `ChatGPTEnhancer/Sources/Diagnostics` | Active / Experimental | diagnostics/probe modules | Alpha55 runtime observed stable genuine `pop 3→2 / push 2→3` public navigation mutations versus custom-route `setViewControllers 0→1`; exact init/prepare/detail alone still did not visibly refresh. Alpha56 adds stable per-process navigation-instance tokens and foreground attachment/key/active snapshots around the same-current route. Alpha56 CI/artifact passed; runtime pending. Diagnostics do not mutate navigation or prove a production refresh mechanism. |
| `.github/workflows/build-enhancer.yml` | Active | Enhancer CI | Current enhancer CI/artifact path on `feat/chatgpt-enhancer-v0.1`; feature-branch trigger is temporary per isolated candidate build and removed after CI. |
| `GPTWebKit/` native app source | Legacy candidate | legacy branches | Native/utility line retained in repository; not current enhancer baseline. |
| `.github/workflows/build-ipa.yml` | Legacy active-on-branches | legacy IPA CI | Builds older native/WebView app artifacts. |

## Allowed statuses

Use concise statuses such as Active, Candidate, Stable, Frozen, Experimental, Deprecated, or Unknown / Unverified.

## Frozen rule

No product module is marked Frozen by initialization. Do not infer Frozen/Stable merely from age or CI success.

Before changing a Frozen or Stable core module for an unrelated task, stop and verify whether the current task truly requires it. Record the concrete reason/evidence before changing the contract.

## Auto-refresh rule

Update this matrix when modules are added, ownership changes, a module becomes stable/frozen, a frozen decision is reopened, or a new candidate supersedes an old baseline.