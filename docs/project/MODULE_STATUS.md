# Module Status

| Module | Status | Owner / baseline | Notes |
|---|---|---|---|
| `ChatGPTEnhancer/Sources/Bootstrap` | Active | `CEBootstrap` | Single constructor/startup owner for enhancer. Alpha60 continues starting runtime diagnostics from this existing owner; no second startup owner exists. |
| `ChatGPTEnhancer/Sources/Core` | Active / Shared core | `CECore`, `CEConversationContext` | Generic UIKit helpers and sole active conversation context. Alpha60 changes candidate version only; identity semantics are unchanged. Shared state owner; conflict-check before parallel edits. |
| `ChatGPTEnhancer/Sources/Network` | Active / Shared core | `CENetworkObserver`, `CEAPIClient` | Observer owns passive host-network observation; API client remains sole enhancer-originated request path. Alpha58/59 transport evidence is retained; alpha60 adds no new replay or request owner. HTTP 429 remains terminal for the current enhancer request. |
| `ChatGPTEnhancer/Sources/Storage` | Active | `CECatalog` | Conversation ID/title/update-time catalog. |
| `ChatGPTEnhancer/Sources/UI` | Active / Shared surface | `CEEnhancerUI`, `CEConversationUIReloadEvidence` | Host UI integration plus ephemeral Reload proof. Alpha59 real-device test showed detail→prepare can occur with no UI rebuild; request/prepare delivery remains insufficient completion evidence. |
| `ChatGPTEnhancer/Sources/Export` | Active | `CEMarkdownExporter` | Complete-conversation Markdown export path. |
| `ChatGPTEnhancer/Sources/Features` | Active | Feature-specific modules | Exact-ID Sync/Reload/Rename behavior. Current Sync still performs enhancer GET then existing manual Reload handoff; alpha60 intentionally does not change production behavior. |
| `ChatGPTEnhancer/Sources/Diagnostics` | Active / Experimental | diagnostic/probe modules | Alpha60 repairs `CEHostRuntimeOwnerTrace` ownership mapping by canonicalizing image paths, verifying method IMP image base via `dladdr`, resolving known App `1.2026.202` offsets directly, and inventorying bounded app-bundle semantic runtime classes/images. It invokes/swizzles none of the discovered methods and persists no raw pointers or sensitive payloads. |
| `.github/workflows/build-enhancer.yml` | Active | Enhancer CI | Alpha60 artifact names are current; normal push trigger restored to `feat/chatgpt-enhancer-v0.1` after isolated recognition build. |
| `GPTWebKit/` native app source | Legacy candidate | legacy branches | Native/utility line retained in repository; not current enhancer baseline. |
| `.github/workflows/build-ipa.yml` | Legacy active-on-branches | legacy IPA CI | Builds older native/WebView app artifacts. |

## Allowed statuses

Use concise statuses such as Active, Candidate, Stable, Frozen, Experimental, Deprecated, or Unknown / Unverified.

## Frozen rule

No product module is currently Frozen/Stable. Do not infer Frozen/Stable merely from age, CI success or Artifact production.

## Current candidate

- Recognition candidate: `0.1.0-alpha60-runtime-image-map`.
- Build/test source `8d371801c764b4a8da95e44e74c0a99fa3a0b126`; Actions `33274357066`, job `99158361042`; post-CI cleanup/current PR head `c0431e83d29299d8da22d2e8089e392a0936511d`.
- Validation: **Code written → CI passed → Artifact produced; Runtime/manual pending**.
- Runtime acceptance is diagnostic. Alpha59's `hostClasses=0` result is not accepted as proof of a pure-Swift path because raw image-path equality was a known blind spot. Alpha60 must independently test canonicalized path ownership, method IMP image-base ownership and direct `dladdr` symbol resolution.

## Auto-refresh rule

Update this matrix when modules are added, ownership changes, a module becomes stable/frozen, a frozen decision is reopened, or a new candidate supersedes an old baseline.