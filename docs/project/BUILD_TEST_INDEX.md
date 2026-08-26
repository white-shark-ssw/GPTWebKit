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
- Legacy IPA workflow currently uses an explicit artifact candidate name independent of the Xcode build number. Treat this as a separate identity namespace from enhancer candidates.

## Candidate table

| Candidate | Work ID | Version / Build / Tag | Branch / PR | Commit | Validation | Artifact | Runtime result | Status |
|---|---|---|---|---|---|---|---|---|
| `ENH-0.1.0-alpha46-conversation-identity-trace` | `DEV-conversation-recognition` | `0.1.0-alpha46-conversation-identity-trace`; Actions `32950198256` | `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1` | Build/test source `fc78d7d525969699fbd15a3f180e563e93e6d424`; CI bookkeeping `a99a9b99ec9c26e3537ee5a242f0cfa7c4764f88`; post-CI cleanup head `96d845e7d750ea178ff73c12faed115dff33d14c` | Code written; CI passed; Artifact produced | package id `9599824714`, digest `sha256:0e8a35affb33f7f1b359dfb9e62c5ddaf95e5f72e3c3b198dedf496050ba32b9`; dylib id `9599825427`, digest `sha256:61de097c001094c512d651825df2d904369911443a032787e349192c3c4e9e95` | Runtime/manual pending. Instrumentation-only candidate: persistent sanitized menu/network/Share trace must be exercised across normal/project/duplicate-title/cold-relaunch cases before any identity design conclusion. | Candidate |
| `ENH-0.1.0-alpha45-visible-button-guard` | `DEV-conversation-recognition` | `0.1.0-alpha45-visible-button-guard`; Actions `32939338703` | `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1` | Build/test source `037b4aba99b45f30e04a8f9714231a545a0137c2`; CI bookkeeping `f28c7f56cfaea48f35cb98ecb20490686f36b54f`; post-CI cleanup `c902d0f1a76d65dd3ba2232dd88eae2b1ac269d8` | Code written; CI passed; Artifact produced; Runtime/manual partially tested | package id `9595962373`, digest `sha256:04e46a8f48643fee95968161798b74a8cb7b963beeadc0e2fab14a339fbeb839`; dylib id `9595962949`, digest `sha256:7868dbe9a0ba84ae0985bb8cea2c136640a5b6c13e7b1b5596a11982e2e97c59` | **NOT ACCEPTED 2026-08-26**: project chat can still refuse Reload with `无法确认当前可见会话，已取消重载。`; menu-scoped enhancer Rename resolves the correct title but exact ID remains unproven | Runtime investigation / not accepted |
| `ENH-0.1.0-alpha44-current-conversation-guard` | `DEV-conversation-recognition` | `0.1.0-alpha44-current-conversation-guard`; Actions `32937976994` | `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1` | Build/test source `668540cbabf300d08c929a1daa057ea4959f2f01`; CI bookkeeping `ec8642391f40ae28a7f3dce8ddec983826ba76db`; post-CI cleanup `a4414cbdd5466cd7bb3d660f43039204dfb052dd` | Code written; CI passed; Artifact produced; Runtime/manual failed | package id `9595516821`, digest `sha256:c084a7e6bce60d4df0a7378ae351b75a2de0669d898fd5f9a019e504c791eb99`; dylib id `9595517523`, digest `sha256:e36cfdd0571b9ee34fb629e58f066947b231602194c2a1301b17c5ab2a28c7a9` | **FAILED 2026-08-26**: floating button not visible; cross-conversation stress acceptance was not completed | Rejected runtime |
| `ENH-0.1.0-alpha43-conversation-usage` | `DEV-conversation-usage` | `0.1.0-alpha43-conversation-usage`; Actions `32857881847` | `feat/conversation-usage`; Draft PR #3 → `feat/conversation-recognition` (stacked on alpha42) | stacked merge `4662fda538fe01e6d5a4530cecde1a249b09e089`; tested product source `41749c039d0ef8a8a7f8e89e6e3508d4d9de3dae`; post-CI cleanup `ddd5829b563a9191ad2687378123d9e53fbb232d` | Code written; CI passed; Artifact produced; embedded recognition dependency rejected | package id `9566922573`, digest `sha256:16f687975b52dc141c28d69acb8c8d8407721be6a9fd05f65496a5861691985b`; dylib id `9566923485`, digest `sha256:affd0b8cf7cf8aae8976ae383d81e5fcbcea393086595523ac5b75cd4c3171a2` | Percentage runtime/manual pending; embedded alpha42 recognition dependency known failed | Candidate with rejected stacked dependency |
| `ENH-0.1.0-alpha42-project-conversation-title` | `DEV-conversation-recognition` | `0.1.0-alpha42-project-conversation-title`; Actions `32855687010` | `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1` | Build/test source `7a68a86ae5091a270aafb18b98b6a4037a1b4f0b`; CI bookkeeping `1494d048fe7cdf43b30b9a29ccb62e3f38644d59`; cleanup `51bc4a9b580d62e3cc95cc3cf95b33827d6a0a7b` | Code written; CI passed; Artifact produced; Runtime/manual real-device failed | package id `9566065953`, digest `sha256:99ba0406e9e959cbf175f828ce1be181a14cf0b0dea001ec3e63e9013a8f620f`; dylib id `9566066411`, digest `sha256:c272d7ccdcad893813c55f8e63de7db7d603cadad96ab8d5a15f0519a9fca162` | **FAILED 2026-08-26**: Pull Latest and Reload can cross/wrong conversations; requested header replacement also had no visible effect | Rejected runtime |
| `ENH-0.1.0-alpha41-project-conversation-title` | `DEV-conversation-recognition` | `0.1.0-alpha41-project-conversation-title`; Actions `32854457168`, `32854676896` | `feat/conversation-recognition`; Draft PR #2 | initial `a6adc52e1b5c75e4a8aa901324a511d328398a1a`; follow-up `9966628eb86d6e60f5cc642e792ee3cc6bf63f6e` | Code written; CI passed; Artifact produced | recorded in historical evidence | Not runtime tested; superseded pre-runtime | Superseded pre-runtime |
| `ENH-0.1.0-alpha40-conversation-recognition` | `DEV-conversation-recognition` | `0.1.0-alpha40-conversation-recognition`; Actions `32850463066` | `feat/conversation-recognition`; Draft PR #2 | Build/test `a7f1aba4848899ec7e5b5cdfd711b584a45d4bdd` | Code written; CI passed; Artifact produced | recorded in historical evidence | Runtime not separately completed before later lineage failed | Superseded |
| `ENH-0.1.0-alpha39-reload-stability` | Pre-governance / unassigned | `0.1.0-alpha39-reload-stability`; Actions `32841238704` | `feat/chatgpt-enhancer-v0.1` | Build `70905cc5d038d41a900e626f0c6467c5d0573ef9` | Code written; CI passed; Artifact produced | recorded by Actions | Unknown / Unverified for alpha39 specifically | Historical candidate |

## Historical / non-current identities

- Legacy native app Xcode version on scanned branch: `MARKETING_VERSION=0.3.0`, `CURRENT_PROJECT_VERSION=2`.
- Legacy IPA workflow artifact string: `ChatGPT-MD-0.3.0-alpha2`.
- Draft PR #1 (`feat/initial-ios-shell`) is the older WebView shell and has no authority over the current enhancer candidate identity.

## Uniqueness rule

Different Active tasks must not reuse the same exact candidate identity, build number, version/build tuple, artifact name, release tag or candidate ID.

Once allocated, an Active candidate identity is reserved until explicitly completed/released and documented.

## Evidence labels

- Code written
- Static/local checks passed
- CI passed
- Artifact produced
- Runtime/manual/real-device tested
- Stable / frozen