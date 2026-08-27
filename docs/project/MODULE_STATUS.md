# Module Status

| Module | Status | Owner / baseline | Notes |
|---|---|---|---|
| `ChatGPTEnhancer/Sources/Bootstrap` | Active | `CEBootstrap` | Single constructor/startup owner for enhancer. New constructors are prohibited by current architecture. |
| `ChatGPTEnhancer/Sources/Core` | Active / Shared core | `CECore`, `CEConversationContext` | Generic UIKit helpers and active conversation context. Shared state owner; conflict-check before parallel edits. |
| `ChatGPTEnhancer/Sources/Network` | Active / Shared core | `CENetworkObserver`, `CEAPIClient` | Observer owns official request template/events and the existing NSURLSession hook surface; alpha54 only invokes diagnostic trace at those existing task-creation hooks. API client remains sole enhancer-originated request path. Sensitive headers stay memory-only. |
| `ChatGPTEnhancer/Sources/Storage` | Active | `CECatalog` | Conversation ID/title/update-time catalog and title resolution. |
| `ChatGPTEnhancer/Sources/UI` | Active / Shared surface | `CEEnhancerUI` | Owns host-app UI integration. Feature modules should not create independent UIKit hook ownership. |
| `ChatGPTEnhancer/Sources/Export` | Active | `CEMarkdownExporter` | Complete-conversation Markdown export path. |
| `ChatGPTEnhancer/Sources/Features` | Active | Feature-specific modules | Exact-ID Sync/Reload/Rename behavior; alpha52+ retains request+UI completion semantics and delivery-aware route suppression. |
| `ChatGPTEnhancer/Sources/Diagnostics` | Active / Experimental | diagnostics/probe modules | Alpha54 adds task-creation-level `REFRESH-CREATE`, ID-less init/prepare staging and bounded navigation-stack composition. CI/artifact passed; runtime pending. Diagnostic presence is not proof of a production refresh mechanism. |
| `.github/workflows/build-enhancer.yml` | Active | Enhancer CI | Current enhancer CI/artifact path on `feat/chatgpt-enhancer-v0.1`. |
| `GPTWebKit/` native app source | Legacy candidate | legacy branches | Native/utility line retained in repository; not current enhancer baseline. |
| `.github/workflows/build-ipa.yml` | Legacy active-on-branches | legacy IPA CI | Builds older native/WebView app artifacts. |

## Allowed statuses

Use concise statuses such as Active, Candidate, Stable, Frozen, Experimental, Deprecated, or Unknown / Unverified.

## Frozen rule

No product module is marked Frozen by initialization. Do not infer Frozen/Stable merely from age or CI success.

Before changing a Frozen or Stable core module for an unrelated task, stop and verify whether the current task truly requires it. Record the concrete reason/evidence before changing the contract.

## Auto-refresh rule

Update this matrix when modules are added, ownership changes, a module becomes stable/frozen, a frozen decision is reopened, or a new candidate supersedes an old baseline.