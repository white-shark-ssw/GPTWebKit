# Project State

_Last updated: 2026-08-26._

## Current accepted baseline

- **Stable/Frozen runtime baseline**: `Unknown / Unverified`.
- `feat/chatgpt-enhancer-v0.1` remains the product base at `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8`.
- `feat/conversation-recognition` is the newest recognition test branch, but no recognition candidate is accepted until real-device stress testing passes.

## Current development candidates

### ChatGPTEnhancer `0.1.0-alpha45-visible-button-guard`

- Work ID `DEV-conversation-recognition`; branch `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1`.
- Build/test source `037b4aba99b45f30e04a8f9714231a545a0137c2`; Actions bookkeeping `f28c7f56cfaea48f35cb98ecb20490686f36b54f`; current branch head `c902d0f1a76d65dd3ba2232dd88eae2b1ac269d8` (post-CI trigger cleanup only). Compare from tested source to current head changes only `.github/latest-enhancer-run-id` and workflow trigger cleanup.
- Alpha45 retains alpha44's identity safety: generic official/background conversation requests do not mutate foreground `CEConversationContext`; Pull/Reload/floating Export require fresh visible proof and fail closed when proof is unavailable.
- Alpha45 fixes the alpha44 UI lifecycle regression by decoupling floating-button visibility from `CEConversationContext.conversationID`. The button attaches whenever the app has a key window; button visibility is UI state only and is not conversation-identity evidence.
- CI passed: run `32939338703`, job `98086902604`.
- Artifacts: package id `9595962373`, digest `sha256:04e46a8f48643fee95968161798b74a8cb7b963beeadc0e2fab14a339fbeb839`; dylib id `9595962949`, digest `sha256:7868dbe9a0ba84ae0985bb8cea2c136640a5b6c13e7b1b5596a11982e2e97c59`.
- Runtime/manual/real-device: **Pending**. First verify the button is visible, then stress-test repeated A↔B switching plus idle/background activity. Pull/Reload/Export must target the visibly open conversation or explicitly refuse, never another conversation.
- Status: Candidate; not Stable/Frozen.

### Rejected `0.1.0-alpha44-current-conversation-guard`

- Alpha44 addressed the proven network-driven identity contamination and passed Actions `32937976994` with artifacts.
- Real-device result on 2026-08-26: **floating button not visible**. Source confirms `CEFloatingButtonController.contextChanged:` hid the button whenever `CEConversationContext.conversationID` was empty. Removing generic network identity writes made that empty state legitimate, so the entry point could disappear.
- Alpha44 is rejected as a usable candidate; its cross-conversation stress acceptance was not completed before this blocker.

### Rejected `0.1.0-alpha42-project-conversation-title`

- Actions `32855687010` passed and artifacts were produced, but real-device testing on 2026-08-26 **failed**.
- User reports that after extended use both Pull Latest and Reload still cross/wrong conversations. Source later proved generic network request IDs could overwrite foreground identity.
- The project-header conversation-title replacement also had no visible effect. That cosmetic issue remains deferred until recognition is safe.

### Parallel `0.1.0-alpha43-conversation-usage`

- Work ID `DEV-conversation-usage`; branch `feat/conversation-usage`; Draft PR #3 is stacked on the earlier alpha42 recognition branch.
- Its percentage-specific CI/artifacts remain separate evidence, but the embedded alpha42 recognition dependency is rejected. The percentage task must re-stack/revalidate after a recognition candidate is accepted.

### Earlier alpha41 / alpha40 / alpha39

- Alpha41 was superseded pre-runtime after synthetic project-header text was found capable of feeding identity paths.
- Alpha40 compiled/produced artifacts but was not separately accepted on device before the later alpha42 lineage failed.
- Alpha39 exact-current reload contract remains architectural history, but the base lineage has known stale/current-conversation problems.

### Legacy/native tracks

- `feat/initial-ios-shell` / Draft PR #1 and `feat/0.2-native-recovery-exporter` remain legacy, not the current enhancer baseline.

## Current architecture

1. `CEBootstrap` — startup owner.
2. `CECore` / `CEConversationContext` — authoritative active conversation state and shared UI helpers.
3. `CEContextResolver` — visible UIKit/catalog-backed current-conversation proof; no generic network-task identity writer.
4. `CENetworkObserver` — passive official-network observation/template/event/catalog input; observed requests do not determine foreground conversation identity.
5. `CEAPIClient` — sole enhancer-originated request owner.
6. `CECatalog` — conversation ID/title/project catalog.
7. `CEEnhancerUI` — host UIKit integration, floating tool lifecycle and action-time visible-conversation verification. Floating-button visibility is not identity evidence.
8. Features/Export/Diagnostics consume those owners.

## Current development direction

- Eliminating cross-conversation execution is the highest priority. False-negative refusal is acceptable while wrong-conversation execution is not.
- Foreground identity must be independently supported by currently visible evidence; generic official background/request traffic is not foreground authority.
- Pull/reload/export must fail closed at the consumer/action boundary when exact visible identity cannot be proven.
- The floating tool entry must remain reachable independently of identity proof so failed recognition can be surfaced/tested without restoring stale-ID behavior.
- Project-header title replacement is deferred until the identity invariant passes repeated real-device testing.
- `DEV-conversation-usage` remains isolated; do not silently merge its alpha43 state into alpha45.

## Known issues / constraints

- ChatGPT private backend/runtime/UI surfaces can change.
- No verified automated unit/UI test suite exists; CI build success is not runtime proof.
- Brand-new uncatalogued conversations or duplicate titles can intentionally produce “无法确认当前可见会话”.
- Project chats may expose less direct visible identity than ordinary chats; guarded actions intentionally refuse rather than fall back to a stale ID.
- Alpha45's always-available floating button may also appear when no conversation is currently proven; that is intentional UI behavior and must not be interpreted as identity success.
- GitHub Actions writes run IDs back to branches; current head can differ from tested source by bookkeeping/workflow-only commits.

## Evidence rule

Always distinguish Code written, Static/local checks passed, CI passed, Artifact produced, Runtime/manual/real-device tested, and Stable/Frozen.
