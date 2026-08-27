# Project State

_Last updated: 2026-08-27._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- Product base `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha55-navigation-mutation-trace`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `64038907a5e4daadf1f7917558ea82c19aa2c5c7`; CI bookkeeping `f1562b55d9848b55e84c902a95b685ce6c0aeb1a`; post-CI cleanup head `4fba1dd7d450666510f83ec0d10e612e6e2a7290`.
- CI passed: Actions `33046416498`, job `98431347604`.
- Artifacts: package id `9635814798`, digest `sha256:2edbf8e2a7cc7b9f96ec907fd4fb396f8ef96ba723e987cd8587b264ef78a62e`; dylib id `9635815423`, Actions archive digest `sha256:9f6b3e1bd95465c426efdecbfb14dc748a6bb34eed4817bddeb6c7027e9792b4`.
- Extracted dylib: arm64 Mach-O, sha256 `616bf42340b9d5934d09fea9a0f8ac04a4174dff3e0fdf92f2f5b7a9bc61560c`.
- Tested source → cleanup head changes only run-id bookkeeping and temporary recognition-branch CI trigger removal; tested product source is unchanged.
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

## Current diagnostic behavior

- Production Sync/Reload behavior remains alpha52+: exact current ID, truthful refresh-request wording, request+UI completion proof, suppression of additional exact-route delivery after one same-ID request is proven, and terminal HTTP 429 handling.
- Alpha54 runtime rejected the specific Objective-C NSURLSession task-creation-selector hypothesis: `REFRESH-CREATE=0` while downstream semantic request traces existed.
- Alpha55 therefore follows the proven state difference instead of expanding network tracing. During the existing user-started identity trace it passively observes public `UINavigationController` stack mutation entry points and emits `NAV-MUTATION` only when stack count/class composition changes.
- `NAV-MUTATION` records selector source, before/after bounded class composition, visible controller class, main-thread/animated flags, exact current context ID and bounded sanitized caller symbols.
- Alpha55 does not call navigation APIs to change the host, does not hard-code private Swift classes and originates no new request.

## Authoritative runtime finding retained

Alpha54 trace `conversation-identity-1995A79E-71DF-4EBC-BB1E-A61D48871FD2.log`, app `1.2026.202`:

- Genuine navigation showed ID-less init/prepare staging at navigation depth 2, then exact target init/prepare/detail at depth 3.
- Same-current Sync/custom-route refresh produced detail only, no exact init/prepare, no UI rebuild, and a one-controller navigation stack.
- Delivery-aware suppression prevented repeat route bursts.
- The semantic requests did not hit the alpha54 swizzled Objective-C NSURLSession task-creation selectors, so that creation-path diagnostic route is rejected.

## Existing architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation identity authority.
3. `CENetworkObserver` — passive host-network observation; only validated exact `POST /backend-api/conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current enhancer request.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — current exact-ID menu integration and row-scoped sidebar Rename/Export.
7. `CEConversationUIReloadEvidence` — ephemeral UI refresh/rebuild proof, never identity authority.
8. `CEConversationIdentityTrace` — optional sanitized runtime evidence, never identity authority; alpha55 adds passive public navigation-mutation observation.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43.
- Alpha55 does not modify percentage-owned source/checkpoint.

## Next evidence

- Install alpha55 and capture one trace: A visible → normal A→B→A → one `同步最新消息` attempt on A → final status → export.
- Compare `NAV-MUTATION` selector/caller and before/after stack transitions between genuine navigation and same-current custom-route refresh.
- Do not implement a production navigation mutation merely because a diagnostic selector is observed; production use requires stable host-owned runtime evidence.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.