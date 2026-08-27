# Project State

_Last updated: 2026-08-27._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- Product base `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha57-navigation-rebuild-proof`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `fe48c56350720127786670d9fe37e28280905055`; CI bookkeeping `ef75624e24e60842afabde93f4151a39453f1c9f`; post-CI cleanup head `ad4a4718c498a9926ed553797ac9fb3e45df48c4`.
- CI passed: Actions `33083945220`, job `98558346397`.
- Artifacts: package id `9651296956`, digest `sha256:c71bfab996a1f01a0634701b95bafb12111863dcc97e3bb4469728e567630cae`; dylib id `9651298129`, Actions archive digest `sha256:ccf2275eded12bd180741ef82d3685b1be21a8da33c8cf01c8b9cea823755fe3`.
- Extracted dylib: Mach-O 64-bit arm64, 614096 bytes, sha256 `2d7de7f8b424d62ba970bf8913da5b0f64ed11d60108d06db5a3b2a9b62a8a3d`.
- Tested source → cleanup head changes only run-id bookkeeping and temporary recognition-branch CI trigger removal; tested product source is unchanged.
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

## Runtime evidence driving alpha57

Alpha56 trace `62313B1B-56B2-4F4C-A1B3-A658FDE8067D`, app `1.2026.202`:

- User visibly observed a page refresh after `同步最新消息`, while alpha56 incorrectly ended with `已请求客户端刷新，但页面未发生刷新。`.
- Reload began with active attached key-window navigation controller `nav-1`, count 3.
- The same-current route emitted a distinct `setViewControllers: 0→1`, then exact same-ID init/prepare/detail.
- Verification resolved a **different** active attached key-window navigation controller `nav-2`, count 1. This proves the host replaced the active navigation-controller surface.
- Exact same-ID request delivery was present and repeat-route suppression worked.
- The old scroll/anchor-only UI detector had `baselineUI=unproven`, causing the false negative.

## Current Sync/Reload behavior

- `CEConversationContext` remains the sole active conversation identity authority.
- `同步最新消息` uses the frozen exact ID and one guarded enhancer GET. HTTP 429 remains terminal for that request; no burst retry.
- Server GET/init/prepare/detail or custom-route acceptance alone is not visible synchronization.
- Visible success still requires exact same-ID request evidence plus UI rebuild evidence.
- Alpha57 adds one evidence-backed UI path: if the currently active attached `UINavigationController` object is replaced between baseline and verification, that replacement counts as an ephemeral UI rebuild signal.
- Existing scroll-view replacement / anchor-turnover proof remains supported.
- Navigation object identity is in-memory UI evidence only; it is not persisted, is not conversation identity, and does not authorize enhancer-originated push/pop/setViewControllers.

## Existing architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation identity authority.
3. `CENetworkObserver` — passive host-network observation; only validated exact `POST /backend-api/conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current enhancer request.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — current exact-ID menu integration and row-scoped sidebar Rename/Export.
7. `CEConversationUIReloadEvidence` — ephemeral UI refresh/rebuild proof; alpha57 includes active attached navigation-controller replacement in addition to scroll/anchor evidence.
8. `CEConversationIdentityTrace` / navigation diagnostics — optional sanitized runtime evidence, never identity authority.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43.
- Alpha57 does not modify percentage-owned source/checkpoint.

## Next evidence

- Install alpha57 and press `同步最新消息` on the same current conversation.
- If the page visibly refreshes, the final status should now be `✓ 当前会话页面已刷新` rather than the alpha56 false negative.
- Do not mark Stable/Frozen until this exact artifact is runtime tested.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.