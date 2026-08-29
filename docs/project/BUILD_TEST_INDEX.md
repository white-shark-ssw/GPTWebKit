# Build / Test / Release Index

This file is the durable index for testable identities and evidence.

## Current identity scheme

### Current ChatGPTEnhancer track

- Product version is the alpha candidate string in `CEVersion` (`ChatGPTEnhancer/Sources/Core/CECore.mm`).
- `ChatGPTEnhancer/build.sh` ZIP name and `.github/workflows/build-enhancer.yml` artifact names must match that candidate string.
- GitHub Actions run ID is build evidence and is recorded in `.github/latest-enhancer-run-id`; it is not a substitute for the product candidate name.
- New parallel Active development tasks must allocate different exact candidate/artifact identities before producing testable artifacts.

### Legacy native app track

- `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` come from `GPTWebKit.xcodeproj/project.pbxproj`.
- Legacy IPA workflow uses an explicit artifact candidate identity independent of the enhancer namespace.

## Candidate table

| Candidate | Work ID | Branch / PR | Build / source | Validation / artifact | Runtime result | Status |
|---|---|---|---|---|---|---|
| `ENH-0.1.0-alpha60-runtime-image-map` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1` | `0.1.0-alpha60-runtime-image-map`; source `8d371801c764b4a8da95e44e74c0a99fa3a0b126`; Actions `33274357066`; job `99158361042`; CI bookkeeping `192ad870a1fb8417d0616ff941966ad4049ab7f5`; cleanup head `c0431e83d29299d8da22d2e8089e392a0936511d` | Code written; CI passed; Artifact produced. Package id `9721043070`, digest `sha256:a08284ace0c5ae8bd381ec5515d4ffc5cfda39b02a3186a4806aa29a4283ff03`; dylib id `9721043178`, digest `sha256:297f910d780a19e3f0212cb1c6fb9cb006144847c281f2e0ee406bf0f9c82338`; extracted dylib 634272 bytes, sha256 `1b227794c9133f022a26bc3a59aa60091984a06b7a31545f0fc840ce10ef0e95` | Pending. Diagnostic-only correction for alpha59's raw image-path ownership blind spot: canonical path comparison, method-IMP image-base verification, direct `dladdr` of known App `1.2026.202` offsets, bounded app-bundle semantic runtime class/image inventory. No private selector invocation/replay/navigation mutation. | **Current recognition candidate** |
| `ENH-0.1.0-alpha59-runtime-owner-map` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | `0.1.0-alpha59-runtime-owner-map`; source `76f83fcf6a53bebd4c8067b2bde44a4edb4a0dfc`; Actions `33273831978`; job `99156971862`; cleanup head `e86b8670fb8de4888e76fdc41f84f4e226275136` | Code written; CI passed; Artifact produced; Runtime/manual/real-device partially tested. Package `9720892970`; dylib `9720893086`; extracted dylib sha256 `a84a06d9ec29f2e9bdb84d7e35438939f9303d94bf01e969264ef26c0e9aa801` | **PARTIAL RUNTIME 2026-08-30**, trace `897A6818-776A-44FC-84BA-21E0501A6A9A`: official finished-chat entry again emitted exact init→prepare→detail. Reload emitted detail first, then exact prepare ~355 ms later, no exact init, no UI rebuild, same attached `nav-1`, final `requestObserved=YES/uiRebuildObserved=NO`. Runtime mapper returned `hostClasses=0`, but that result is inconclusive because alpha59 used raw image-path equality. | Superseded by alpha60 diagnostic correction |
| `ENH-0.1.0-alpha58-reentry-network-trace` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | `0.1.0-alpha58-reentry-network-trace`; source `c9f9c328386e63fd409421d74d7f18c091144ad2`; Actions `33272953771`; job `99154630406`; cleanup `c0fa017e6bda0a4d91701e687abae3c8d51d3304` | Code written; CI passed; Artifact produced; Runtime/manual partially tested. Package `9720640754`; dylib `9720641009`; extracted sha256 `df6c3f0b7e41b3386769f9df35d10dcb57bee4fee7e8c22c5190192dfd80a061` | Trace `E74DA953-6BB5-4A92-87DF-474142BD37C7`: official entry emitted exact init→prepare→detail on `session-1`; failed Reload showed same low-level session but no UI rebuild. Raw detail replay proved insufficient; successful response/state consumer remained unobserved. | Superseded |
| `ENH-0.1.0-alpha57-navigation-rebuild-proof` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `fe48c56350720127786670d9fe37e28280905055`; Actions `33083945220`; job `98558346397`; cleanup `ad4a4718c498a9926ed553797ac9fb3e45df48c4` | Code written; CI passed; Artifact produced | Later broad real-device testing rejected route-based Sync/Reload as reliable production behavior. | Superseded |
| `ENH-0.1.0-alpha56-navigation-instance-trace` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | accepted source `f2cee73312da7254d44053ec092f9e7643326d92`; Actions `33052999411`; job `98452810620`; cleanup `ce9bf42d6c4d3afde125e01c03120adbdf6f718d` | Code written; CI passed; Artifact produced; Runtime partially tested | Trace `62313B1B-56B2-4F4C-A1B3-A658FDE8067D`: one visible refresh correlated with active nav replacement `nav-1 → nav-2` and exact same-ID init/prepare/detail. Later testing showed this route is not reliable enough as production Reload. | Superseded |
| `ENH-0.1.0-alpha55-navigation-mutation-trace` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `64038907a5e4daadf1f7917558ea82c19aa2c5c7`; Actions `33046416498`; job `98431347604` | Code written; CI passed; Artifact produced; Runtime partially tested | Genuine navigation showed public pop/push patterns; same-current route used different stack behavior. Navigation mutations remain diagnostic evidence only. | Superseded |
| `ENH-0.1.0-alpha54-task-creation-trace` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `6d0f8537cde9d1f3029e4b0a5f39c9a0aa041142`; Actions `33042244321`; job `98418234062` | Code written; CI passed; Artifact produced; Runtime partially tested | Zero selected ObjC NSURLSession task-creation hits while downstream refresh traffic was visible; those selectors are rejected as the upstream semantic-request owner. | Superseded |
| `ENH-0.1.0-alpha53-refresh-path-trace` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `b62878928816c40cbed8c11847a3ed7ae494adde`; Actions `33007145536`; job `98303728684` | Code written; CI passed; Artifact produced; Runtime partially tested | Genuine A→B/B→A emitted init→prepare→detail; failed same-current path delivered detail without visible rebuild. | Superseded |
| `ENH-0.1.0-alpha52-sync-refresh-handoff` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `9c06219cdee1ac00b75372f1480278169b3f6e59`; Actions `33004675627`; job `98295074960` | Code written; CI passed; Artifact produced | Established init→prepare→detail as host-navigation evidence, not a replay recipe. | Superseded |
| `ENH-0.1.0-alpha51-sync-latest-rate-limit` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `bbc8696d7c11f2d6030d7e44cdc3c979f38dba77`; Actions `33000977913`; job `98282430781` | Code written; CI passed; Artifact produced | Exact target held; visible synchronization still failed; no 429 in trace. | Superseded |
| `ENH-0.1.0-alpha50-sidebar-menu-actions` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `44b7baf84458c19c963ce0a7ee0d869da28dfe08`; Actions `32984372907`; job `98228416235` | Code written; CI passed; Artifact produced | Sidebar Rename/Export restored; project-header presentation remained failed/paused. | Superseded |
| `ENH-0.1.0-alpha49-exact-rename-ui-target` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `3f3a04715e93755c1c04b4ca826aad2488c2a9a1`; Actions `32980682467`; job `98216287227` | Code written; CI passed; Artifact produced | Current top-right exact-ID actions usable; sidebar enhancer actions required later restoration. | Superseded |
| `ENH-0.1.0-alpha48-reload-ui-title` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `e2b133f0ba050b485e89129e4fe0ecb9bbee2343`; Actions `32973529739`; job `98192604072` | Code written; CI passed; Artifact produced | UI proof false-negatived one visually observed refresh; interrupted-generation recovery remained unproven. | Not accepted |
| `ENH-0.1.0-alpha47-exact-menu-target` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `d297f65971fb6239cad2be7eb7fa9f8f8aab9f6d`; Actions `32969623709`; job `98180033708` | Code written; CI passed; Artifact produced | Exact-ID current-menu architecture reached device; request-only Reload success was rejected. | Superseded |
| `ENH-0.1.0-alpha46-conversation-identity-trace` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `fc78d7d525969699fbd15a3f180e563e93e6d424`; Actions `32950198256` | Code written; CI passed; Artifact produced; Runtime instrumentation tested | Explicit `conversation/init` body ID matched Share ground truth including duplicate titles/cold relaunch; arbitrary menu/config UUIDs did not. | Runtime evidence complete; superseded |
| `ENH-0.1.0-alpha45-visible-button-guard` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `037b4aba99b45f30e04a8f9714231a545a0137c2`; Actions `32939338703` | Code written; CI passed; Artifact produced; Runtime partially tested | Project chat could false-negative current visible proof. | Not accepted |
| `ENH-0.1.0-alpha44-current-conversation-guard` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `668540cbabf300d08c929a1daa057ea4959f2f01`; Actions `32937976994` | Code written; CI passed; Artifact produced; Runtime failed | Floating button not visible; cross-conversation acceptance incomplete. | Rejected |
| `ENH-0.1.0-alpha43-conversation-usage` | `DEV-conversation-usage` | `feat/conversation-usage`; Draft PR #3 → `feat/conversation-recognition` | tested source `41749c039d0ef8a8a7f8e89e6e3508d4d9de3dae`; Actions `32857881847`; cleanup `ddd5829b563a9191ad2687378123d9e53fbb232d` | Code written; CI passed; Artifact produced. Package `9566922573`; dylib `9566923485` | Percentage runtime/manual pending; embedded old recognition dependency requires reconciliation before next final validation. | Parallel candidate |
| `ENH-0.1.0-alpha42-project-conversation-title` | `DEV-conversation-recognition` | `feat/conversation-recognition`; Draft PR #2 | source `7a68a86ae5091a270aafb18b98b6a4037a1b4f0b`; Actions `32855687010` | Code written; CI passed; Artifact produced; Runtime failed | Pull/Reload could cross conversations; project header had no visible effect. | Rejected |

## Historical / non-current identities

- Older enhancer alpha history remains available in Git history and PR #2; the table above retains all candidates that materially define the current recognition/usage contracts.
- Legacy native app Xcode version on scanned branch: `MARKETING_VERSION=0.3.0`, `CURRENT_PROJECT_VERSION=2`.
- Legacy IPA workflow artifact string: `ChatGPT-MD-0.3.0-alpha2`.

## Uniqueness rule

Different Active tasks must not reuse the same build number, exact version/build tuple, artifact name, release tag or candidate ID. Once allocated, an Active candidate identity is reserved until explicitly completed/released and documented.

## Evidence labels

- Code written
- Static/local checks passed
- CI passed
- Artifact produced
- Runtime/manual/real-device tested
- Stable / frozen
