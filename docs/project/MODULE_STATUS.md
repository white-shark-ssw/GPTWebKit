# Module Status

| Module | Status | Owner / baseline | Notes |
|---|---|---|---|
| `ChatGPTEnhancer/Sources/Bootstrap` | Active | `CEBootstrap` | Single constructor/startup owner for enhancer. Alpha59 starts the runtime-owner diagnostic from this existing owner; no second constructor/startup owner was added. |
| `ChatGPTEnhancer/Sources/Core` | Active / Shared core | `CECore`, `CEConversationContext` | Generic UIKit helpers and sole active conversation context. Shared state owner; conflict-check before parallel edits. Alpha59 changes candidate version only; identity semantics are unchanged. |
| `ChatGPTEnhancer/Sources/Network` | Active / Shared core | `CENetworkObserver`, `CEAPIClient` | Observer owns passive host-network observation; API client remains sole enhancer-originated request path. Alpha58 re-entry transport evidence is retained; alpha59 does not add another network hook/replay. HTTP 429 is terminal for the current enhancer request. Sensitive headers stay memory-only. |
| `ChatGPTEnhancer/Sources/Storage` | Active | `CECatalog` | Conversation ID/title/update-time catalog. |
| `ChatGPTEnhancer/Sources/UI` | Active / Shared surface | `CEEnhancerUI`, `CEConversationUIReloadEvidence` | Host UI integration plus ephemeral Reload proof. Existing nav-replacement / scroll-anchor evidence remains diagnostic completion evidence only; alpha59 does not change UI behavior. |
| `ChatGPTEnhancer/Sources/Export` | Active | `CEMarkdownExporter` | Complete-conversation Markdown export path. |
| `ChatGPTEnhancer/Sources/Features` | Active | Feature-specific modules | Exact-ID Sync/Reload/Rename behavior. Current Sync still performs enhancer GET then existing manual Reload handoff; alpha59 intentionally does not change production Sync/Reload behavior. |
| `ChatGPTEnhancer/Sources/Diagnostics` | Active / Experimental | diagnostic/probe modules | Alpha59 adds `CEHostRuntimeOwnerTrace`: when the user-started trace is active it maps alpha58 App `1.2026.202` main-image stack offsets to nearest Objective-C method IMPs and emits bounded semantic class/selector inventory. It invokes/swizzles none of the discovered methods and persists no raw pointers or sensitive payloads. |
| `.github/workflows/build-enhancer.yml` | Active | Enhancer CI | Alpha59 artifact names are current; normal push trigger is restored to `feat/chatgpt-enhancer-v0.1` after the isolated recognition build. |
| `GPTWebKit/` native app source | Legacy candidate | legacy branches | Native/utility line retained in repository; not current enhancer baseline. |
| `.github/workflows/build-ipa.yml` | Legacy active-on-branches | legacy IPA CI | Builds older native/WebView app artifacts. |

## Allowed statuses

Use concise statuses such as Active, Candidate, Stable, Frozen, Experimental, Deprecated, or Unknown / Unverified.

## Frozen rule

No product module is currently Frozen/Stable. Do not infer Frozen/Stable merely from age, CI success or Artifact production.

## Current candidate

- Recognition candidate: `0.1.0-alpha59-runtime-owner-map`.
- Build/test source `76f83fcf6a53bebd4c8067b2bde44a4edb4a0dfc`; Actions `33273831978`, job `99156971862`; post-CI cleanup/current PR head `e86b8670fb8de4888e76fdc41f84f4e226275136`.
- Validation: **Code written → CI passed → Artifact produced; Runtime/manual pending**.
- Runtime acceptance is diagnostic: determine whether alpha58's official navigation/network frames map closely to a semantically plausible Objective-C owner. A nearby runtime method is not authorization to invoke it; distant/no mapping is useful evidence that the key path may be pure Swift/non-Objective-C.

## Auto-refresh rule

Update this matrix when modules are added, ownership changes, a module becomes stable/frozen, a frozen decision is reopened, or a new candidate supersedes an old baseline.