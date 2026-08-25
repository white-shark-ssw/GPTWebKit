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
| `ENH-0.1.0-alpha43-conversation-usage` | `DEV-conversation-usage` | `0.1.0-alpha43-conversation-usage`; Actions `32857881847` | `feat/conversation-usage`; Draft PR #3 → `feat/conversation-recognition` (stacked on alpha42) | stacked merge `4662fda538fe01e6d5a4530cecde1a249b09e089`; tested product source `41749c039d0ef8a8a7f8e89e6e3508d4d9de3dae`; post-CI bookkeeping/workflow cleanup head `ddd5829b563a9191ad2687378123d9e53fbb232d` | Code written; CI passed; Artifact produced. `41749c0... → ddd5829...` changes only run-id bookkeeping and removal of the temporary usage-branch CI trigger. | package id `9566922573`, digest `sha256:16f687975b52dc141c28d69acb8c8d8407721be6a9fd05f65496a5861691985b`; dylib id `9566923485`, digest `sha256:affd0b8cf7cf8aae8976ae383d81e5fcbcea393086595523ac5b75cd4c3171a2` | Runtime/manual/real-device pending | Candidate |
| `ENH-0.1.0-alpha42-project-conversation-title` | `DEV-conversation-recognition` | `0.1.0-alpha42-project-conversation-title`; Actions `32855687010` | `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1` | Build/test source `7a68a86ae5091a270aafb18b98b6a4037a1b4f0b`; CI bookkeeping `1494d048fe7cdf43b30b9a29ccb62e3f38644d59`; post-CI workflow-only cleanup head `51bc4a9b580d62e3cc95cc3cf95b33827d6a0a7b` | Code written; CI passed; Artifact produced | package id `9566065953`, digest `sha256:99ba0406e9e959cbf175f828ce1be181a14cf0b0dea001ec3e63e9013a8f620f`; dylib id `9566066411`, digest `sha256:c272d7ccdcad893813c55f8e63de7db7d603cadad96ab8d5a15f0519a9fca162` | Runtime/manual/real-device pending | Candidate |
| `ENH-0.1.0-alpha41-project-conversation-title` | `DEV-conversation-recognition` | `0.1.0-alpha41-project-conversation-title`; Actions `32854457168` and follow-up `32854676896` | `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1` | Initial build head `a6adc52e1b5c75e4a8aa901324a511d328398a1a`; follow-up isolation head `9966628eb86d6e60f5cc642e792ee3cc6bf63f6e`; bookkeeping heads `222cf937795448ef909f4bd6c50a09b84eb2daa7` / `96853959eaa175a437ae09b6eb8025f965b55f02` | Code written; CI passed; Artifact produced. Post-build review found synthetic header title could still be consumed by identity paths; candidate not released for runtime acceptance. | Run `32854457168`: package `sha256:e0ed2b538e011bb3d68b4a897c437bfa0bb64415feb065f2c578a31005e8051b`, dylib `sha256:1dd13018ea1c3f248ab9ade9a598cfee96993f630c29c0e5e4150a432296fd0a`. Follow-up run `32854676896`: package `sha256:cdf51bf9c961d85d51fc82218a104b06d671e802a9ff6dc0cd22e960fac359db`, dylib `sha256:3548738b5ea48b22c35c85f93d7f9e5f4e08e4fffe672a0a644abe8cc7eb9323`. | Not runtime tested; intentionally superseded before device acceptance | Superseded pre-runtime |
| `ENH-0.1.0-alpha40-conversation-recognition` | `DEV-conversation-recognition` | `0.1.0-alpha40-conversation-recognition`; Actions `32850463066` | `feat/conversation-recognition`; Draft PR #2 → `feat/chatgpt-enhancer-v0.1` | Build/test head `a7f1aba4848899ec7e5b5cdfd711b584a45d4bdd`; CI bookkeeping `ab5d8d4a5caddfc3dd3fdc88acc065b0036aa8d1`; post-CI branch head `5157425c3b3926ec8150486730301c7d285f24e9` | Code written; CI passed; Artifact produced | `ChatGPTEnhancer-0.1.0-alpha40-conversation-recognition` digest `sha256:776527c8dfa199ddfa2085a02e33dd02c49d4003a8ed170bedc2601411565433`; `...-dylib` digest `sha256:88e734bc5bc0920e45124f02af13ece6e58b2d779eca202a131e45f71dab6292` | Runtime/manual/real-device test pending | Candidate |
| `ENH-0.1.0-alpha39-reload-stability` | Pre-governance / unassigned | `0.1.0-alpha39-reload-stability`; Actions `32841238704` | `feat/chatgpt-enhancer-v0.1`; no PR recorded | Build head `70905cc5d038d41a900e626f0c6467c5d0573ef9`; branch head `c9602a0ccf3060f053f13b121b5c0c5bdf14aaf8` | Code written; CI passed; Artifact produced | `ChatGPTEnhancer-0.1.0-alpha39-reload-stability`, `...-dylib`; artifact digests recorded by GitHub Actions | `Unknown / Unverified` for alpha39 specifically | Candidate |

## Historical / non-current identities

- Legacy native app Xcode version on scanned branch: `MARKETING_VERSION=0.3.0`, `CURRENT_PROJECT_VERSION=2`.
- Legacy IPA workflow artifact string: `ChatGPT-MD-0.3.0-alpha2`.
- Draft PR #1 (`feat/initial-ios-shell`) is the older WebView shell and has no authority over the current enhancer candidate identity.

## Uniqueness rule

Different Active tasks must not reuse the same exact candidate identity, build number, version/build tuple, release tag, artifact name or candidate ID.

Once allocated, an Active candidate identity is reserved until explicitly completed/released and documented.

## Evidence labels

- Code written
- Static/local checks passed
- CI passed
- Artifact produced
- Runtime/manual/real-device tested
- Stable / frozen
