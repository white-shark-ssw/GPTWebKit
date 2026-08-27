# Project State

_Last updated: 2026-08-27._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- Product base `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha56-navigation-instance-trace`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Accepted build/test source `f2cee73312da7254d44053ec092f9e7643326d92`; CI bookkeeping `6b69425e5c2284777b86890d0d967f1d3c45dcf5`; post-CI cleanup head `ce9bf42d6c4d3afde125e01c03120adbdf6f718d`.
- First alpha56 CI run `33052810815`, job `98452184776`, failed at compile because of a diagnostic-only syntax typo and produced no artifact. The corrected accepted build passed Actions `33052999411`, job `98452810620`.
- Artifacts: package id `9638389331`, digest `sha256:c6eab9030b6b4d9b5957fbb864410d0bf0931785ee95d4d4ca098e8d13dae0fb`; dylib id `9638389813`, Actions archive digest `sha256:993c966dd8dbdcc7ceb805d8ad647df5b0dff0a06b97e31b61923792a89d9266`.
- Extracted dylib: arm64 Mach-O, 613776 bytes, sha256 `3af11e471dd986d7074619be4f0b224f28e90ec3b29c73dd31379f4bb37b3b42`.
- Tested source → cleanup head changes only run-id bookkeeping and temporary recognition-branch CI trigger removal; tested product source is unchanged.
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

## Authoritative alpha55 runtime finding

Trace `conversation-identity-F042014D-8407-4910-A5DA-2A9399C26425.log`, app `1.2026.202`:

- Genuine conversation navigation repeatedly used public `UINavigationController` mutation sequence `pop 3 → 2` followed by `push 2 → 3`; caller signatures were stable across repeated switches.
- Genuine target push preceded exact target `conversation/init` by about 128–135 ms, then exact prepare/detail followed. This strengthens that network traffic follows host navigation-state mutation rather than owning it.
- Same-current `同步最新消息` used a different `setViewControllers: 0 → 1` path rather than the genuine pop/push sequence. In this trace the custom route then produced exact init/prepare/detail at navigation depth 1, but the visible conversation still did not rebuild.
- Therefore exact init/prepare/detail is still insufficient for visible refresh; the one-controller navigation state is structurally different from genuine navigation.
- Alpha55 did not record navigation-controller instance identity or attachment. Whether custom-route `0 → 1` belongs to a separate/new/off-path navigation instance remains `Unknown / Unverified`.
- Delivery-aware suppression still prevented repeat route bursts. No HTTP 429 occurred.

## Alpha56 diagnostic behavior

- Production Sync/Reload behavior remains alpha52+: exact current ID, truthful refresh-request wording, request+UI completion proof, suppression of additional exact-route delivery after one same-ID request is proven, and terminal HTTP 429 handling.
- Alpha56 adds evidence-only navigation-instance correlation. Each observed public `UINavigationController` gets a stable per-process diagnostic token without persisting a raw pointer/address.
- Around the existing same-current route handoff, snapshots record stack count/composition, visible controller class, foreground-window attachment, key-window status, whether the instance is the active navigation controller resolved from the top controller, and bounded parent/presentation class metadata.
- Alpha56 does not call navigation APIs to change the host, does not fabricate stack entries, does not hard-code private Swift classes and originates no additional ChatGPT request.

## Existing architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation identity authority.
3. `CENetworkObserver` — passive host-network observation; only validated exact `POST /backend-api/conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current enhancer request.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — current exact-ID menu integration and row-scoped sidebar Rename/Export.
7. `CEConversationUIReloadEvidence` — ephemeral UI refresh/rebuild proof, never identity authority.
8. `CEConversationIdentityTrace` / `CENavigationInstanceTrace` — optional sanitized runtime evidence only, never identity authority.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43.
- Alpha56 does not modify percentage-owned source/checkpoint.

## Next evidence

- Install alpha56 and capture one short trace on an already open target conversation: begin `会话识别记录` → press `同步最新消息` once → wait for final status → finish/export.
- Compare `NAV-INSTANCE` tokens and attachment/active ownership before route open, after route delivery and during verification.
- Do not implement production navigation mutation from count/caller evidence alone. The next production step depends on whether alpha56 proves the custom-route `0 → 1` belongs to a different/off-path instance or replaces/becomes the active host instance.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.