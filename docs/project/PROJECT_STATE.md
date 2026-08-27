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
- Status: **Code written → CI passed → Artifact produced → Runtime/manual/real-device partially tested.**

## Alpha54 runtime evidence — 2026-08-27

Trace `conversation-identity-1995A79E-71DF-4EBC-BB1E-A61D48871FD2.log`, app `1.2026.202`:

- The trace starts on A exact ID `6a8d8d0b-1b2c-83ec-89f4-fa5eb65138d7`.
- Before first exact navigation, the host emitted one ID-less `conversation/init` and two ID-less prepares while public `SwiftUI.UIKitNavigationController` had `navCount=2` with two homogeneous `NavigationStackHostingController<AnyView>` entries.
- Exact navigation to B `6a8da245-c538-83ec-9303-da2952a46a1f` then emitted exact init; exact prepare followed about 118 ms later and exact detail about 123 ms later. Exact B snapshots had `navCount=3` with three homogeneous stack entries.
- Returning to A emitted an additional ID-less prepare while `navCount=3`, then exact A init followed by exact prepare/detail about 123–126 ms later; exact A snapshots remained `navCount=3`.
- Same-A `同步最新消息` targeted the correct exact A ID. Its custom route opened once and produced only one same-ID detail GET with `navCount=1`, no exact init/prepare and no UI rebuild. Delivery-aware suppression stopped further route attempts and the operation reported failure truthfully.
- **Zero `REFRESH-CREATE` records were emitted** despite 14 refresh-relevant `REFRESH-PATH` records. The official semantic init/prepare/detail requests therefore did not traverse the specific swizzled Objective-C NSURLSession task-creation selectors instrumented by alpha54. The exact higher-level Foundation/Swift API is still Unknown / Unverified.
- All 14 downstream `REFRESH-PATH` call-stack signatures were identical. Alpha54 did not identify a production refresh entry point; its task-creation-selector hypothesis is runtime-rejected.
- No HTTP 429 occurred in this trace; terminal 429 handling remains runtime-unexercised by trace evidence.

## Current conclusions

- Exact-current identity remains correct and one-delivery suppression remains device-confirmed.
- Genuine navigation now has stronger structural evidence: ID-less staging can occur at navigation depth 2 before exact target init/prepare/detail at depth 3. The network sequence follows a host navigation-state change and remains evidence, not a replay recipe.
- The same-current custom URL route reaches/collapses to a one-controller navigation state and emits detail only; it is not equivalent to genuine navigation.
- Do not keep expanding diagnostics at the same Objective-C NSURLSession task-creation selectors; this runtime produced no `REFRESH-CREATE` there.
- If continuing, the next diagnostic should observe public `UINavigationController` stack mutation entry points without changing them, recording before/after bounded stack composition and sanitized caller evidence during the user-started trace. This does not authorize stack restoration, push/pop fallback or private-class hard-coding.

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

- If continuing the refresh investigation, instrument only diagnostic observation of public `UINavigationController` stack mutations during the existing user-started trace; keep production Sync/Reload unchanged.
- Then run one A → B → A → `同步最新消息` trace and compare genuine stack transitions with the custom-route collapse.
- Do not implement production navigation mutation, request replay, History/sidebar navigation, alternate IDs, `/resume`, retries/watchdogs/timers or additional route variants without new evidence.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.