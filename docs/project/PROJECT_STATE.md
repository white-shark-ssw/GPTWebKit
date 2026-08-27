# Project State

_Last updated: 2026-08-27._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- Product base `feat/chatgpt-enhancer-v0.1` remains `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition branch. No recognition candidate is Stable/Frozen.

## Current development candidate

### ChatGPTEnhancer `0.1.0-alpha54-task-creation-trace`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `6d0f8537cde9d1f3029e4b0a5f39c9a0aa041142`; CI bookkeeping `fa5338712eea77194548e041472047e1dfe4b931`; post-CI cleanup head `aa00b1d164fd11e8f743e557b33eecd8dcb1bfd1`.
- CI passed: Actions `33042244321`, job `98418234062`.
- Artifacts: package id `9634299997`, digest `sha256:560a89c13222875effba1e15e19d7afada4228ce0b111e2269fc2ecab3957834`; dylib id `9634300301`, Actions archive digest `sha256:506f9db6c6df491a167b51fe0541bf5c7a6bec753efc5b949bdc6e159e494f2e`.
- Extracted dylib: arm64 Mach-O, 594752 bytes, sha256 `cad6d1e1fdcc74b4c1cc25d2d3abed53f8af79b818d04e619073f01544224237`.
- Tested source → cleanup head changes only run-id bookkeeping and temporary recognition-branch CI trigger removal; tested product source is unchanged.
- Status: **Code written → CI passed → Artifact produced. Runtime/manual pending.**

## Current diagnostic behavior

- Production Sync/Reload behavior remains the alpha52+ behavior: exact current ID, truthful refresh-request wording, request+UI completion proof, suppression of additional exact-route delivery once one same-ID request is proven, and terminal HTTP 429 handling.
- Alpha54 adds diagnostic-only `REFRESH-CREATE` records at the existing NSURLSession task-creation hooks for non-enhancer/internal tasks.
- Structural stages are limited to exact `conversation/init`, ID-less `conversation/init` staging, exact `conversation/prepare`, ID-less prepare staging, and exact conversation-detail GET.
- Records include task-creation hook source, target ID if present, key/root/top/presented controller classes, navigation-controller stack count/visible controller, bounded controller-stack class composition and sanitized caller symbols.
- Existing downstream `REFRESH-PATH` now also carries stage + bounded navigation-stack composition, including ID-less init/prepare staging.
- No auth/cookie/account/raw body/message content is persisted. No new traffic is originated by the diagnostic.
- No production refresh mechanism, init/prepare replay, navigation-stack mutation, UIKit pop/push, History/sidebar navigation, alternate ID, `/resume`, timer/watchdog/retry family, Catalog throttling, project-header change or percentage change was added.

## Authoritative alpha53 runtime finding retained

Trace `conversation-identity-E076722C-E0F0-4044-8B99-41F727B1B62B.log`, app `1.2026.202`:

- Genuine exact A→B and B→A navigation emitted exact init then exact prepare/detail within ~125 ms and showed public navigation `navCount=3`.
- Same-A Sync/custom-route handoff produced one detail GET only, no exact init/prepare, no UI rebuild, and `navCount=1`.
- Delivery-aware suppression prevented second/third route attempts after the first same-ID request was proven.
- All 11 alpha53 downstream call-stack signatures were identical, so the old capture point is not upstream host-entry evidence.

## Existing architecture / contracts

1. `CEBootstrap` — sole startup owner.
2. `CECore` / `CEConversationContext` — sole active-conversation identity authority.
3. `CENetworkObserver` — passive host-network observation; only validated exact `POST /backend-api/conversation/init` body ID may promote foreground identity.
4. `CEAPIClient` — sole enhancer-originated ChatGPT request owner; HTTP 429 is terminal for the current enhancer request.
5. `CECatalog` — conversation catalog/title state.
6. `CEEnhancerUI` — current exact-ID menu integration and row-scoped sidebar Rename/Export.
7. `CEConversationUIReloadEvidence` — ephemeral UI refresh/rebuild proof, never identity authority.
8. `CEConversationIdentityTrace` — optional sanitized runtime evidence, never identity authority.

## Parallel task

- `DEV-conversation-usage` remains Active on `feat/conversation-usage` at `ddd5829b563a9191ad2687378123d9e53fbb232d`, candidate alpha43.
- Alpha54 did not modify percentage-owned source/checkpoint.

## Next evidence

- Install alpha54 and capture one trace: A visible → normal A→B→A → one `同步最新消息` attempt on A → final status → export.
- Compare `REFRESH-CREATE` hook/caller signatures, navigation-stack composition, and ID-less init/prepare staging between genuine navigation and same-current custom-route refresh.
- Do not implement a production host refresh mechanism unless the trace identifies an evidence-backed host entry path.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.