# Project Profile

## Initialization

**Initialized** — 2026-08-25 from real repository evidence. Unknown facts remain `Unknown / Unverified`.

## Identity

- **Project name**: `GPTWebKit` repository; current active product track is `ChatGPTEnhancer`.
- **Repository**: `white-shark-ssw/GPTWebKit`.
- **Project purpose**: iOS tooling that augments ChatGPT usage. The newest active track injects a dylib into the official ChatGPT iOS app to add conversation export/management/reload/diagnostic UI. Older branches also contain a standalone/native ChatGPT utility and earlier WebView client experiments.
- **Product type**: Current track — injected iOS dynamic library / host-app enhancer. Legacy tracks — native iOS app / WebView utility.
- **Primary users/runtime**: Current enhancer targets the official ChatGPT iOS app bundle `com.openai.chat`, iOS 17.0+, installed through TrollFools / 巨魔注入器-style plain dylib injection.

## Technology stack

- **Primary language(s)**: Objective-C++ (`.mm`) for `ChatGPTEnhancer`; Swift for the legacy/native `GPTWebKit` app; Bash for build packaging; YAML for GitHub Actions.
- **Framework(s)**: UIKit, Foundation, QuartzCore, CoreGraphics for the enhancer; UIKit/Xcode iOS app target for the legacy native app.
- **Package/dependency manager(s)**: No third-party package/dependency manifest found in the scanned repository tree. `Unknown / Unverified` beyond system Apple frameworks.
- **Important manifests/configs**: `ChatGPTEnhancer/Support/ChatGPTEnhancer.plist`, `ChatGPTEnhancer/build.sh`, `GPTWebKit.xcodeproj/project.pbxproj`, `GPTWebKit/Info.plist`, `.github/workflows/build-enhancer.yml`, `.github/workflows/build-ipa.yml`.

## Repository structure

- **Main source roots**: Current enhancer: `ChatGPTEnhancer/Sources/`; legacy native app: `GPTWebKit/`.
- **Application/service entry points**: Enhancer primary startup entry: `ChatGPTEnhancer/Sources/Bootstrap/CEBootstrap.mm`; legacy app: `GPTWebKit/AppDelegate.swift` + `GPTWebKit/SceneDelegate.swift`.
- **Test roots**: No automated unit/UI test root found in the scanned source tree.
- **Key modules/state owners**:
  - `Core/CECore` — generic UIKit helpers and authoritative active `CEConversationContext` state.
  - `Network/CENetworkObserver` — passive observation of official ChatGPT Foundation networking and in-memory request template/events.
  - `Network/CEAPIClient` — sole owner for enhancer-originated ChatGPT requests.
  - `Storage/CECatalog` — conversation ID/title/update-time catalog and title resolution.
  - `UI/CEEnhancerUI` — host-app UI integration and enhancer surfaces.
  - `Export/CEMarkdownExporter` — Markdown generation from conversation data.
  - `Features/*` — feature behavior such as rename/reload/recovery.
  - `Diagnostics/*` — runtime probes and recovery diagnostics.

## Build and validation

- **Build command(s)**:
  - Current enhancer: `bash ./ChatGPTEnhancer/build.sh` on macOS with Xcode/iPhoneOS SDK.
  - Legacy native app CI: `xcodebuild -project GPTWebKit.xcodeproj -scheme GPTWebKit -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build`.
- **Test command(s)**: No automated test command verified.
- **Lint/static checks**: No dedicated lint/format/static-analysis command verified.
- **CI workflows**:
  - `.github/workflows/build-enhancer.yml` — `Build ChatGPTEnhancer`, macOS 15, normal push branch `feat/chatgpt-enhancer-v0.1`; `DEV-conversation-recognition` was also built once on its isolated branch by Actions run `32850463066` while validating alpha40.
  - `.github/workflows/build-ipa.yml` — legacy unsigned IPA build for `feat/initial-ios-shell` and `feat/0.2-native-recovery-exporter`.
- **Artifact/package output**:
  - Newest enhancer test candidate: `ChatGPTEnhancer.dylib` plus `ChatGPTEnhancer-0.1.0-alpha40-conversation-recognition.zip`; Actions run `32850463066` produced package and dylib artifacts. Runtime/manual acceptance is still pending.
  - Previous enhancer candidate: `0.1.0-alpha39-reload-stability`.
  - Legacy app workflow: unsigned IPA artifact, currently named `ChatGPT-MD-0.3.0-alpha2.ipa` in the workflow.

## Versioning and candidate identity

- **Version source**:
  - Enhancer: `CEVersion` in `ChatGPTEnhancer/Sources/Core/CECore.mm`; package/artifact names are also duplicated in `ChatGPTEnhancer/build.sh` and `.github/workflows/build-enhancer.yml` and must be kept synchronized.
  - Legacy app: `MARKETING_VERSION` in `GPTWebKit.xcodeproj/project.pbxproj` (`0.3.0` on the scanned legacy branch).
- **Build number source**:
  - Enhancer: no separate numeric product build number verified. GitHub Actions run ID is recorded in `.github/latest-enhancer-run-id` as CI/build evidence, not as the product version.
  - Legacy app: `CURRENT_PROJECT_VERSION` in `project.pbxproj` (`2` on the scanned branch).
- **Release/tag scheme**: No repository release/tag process verified. Current enhancer uses semantic alpha candidate strings such as `0.1.0-alpha40-conversation-recognition`.
- **Parallel test-candidate scheme**: Governance rule established: each Active development task must reserve a unique candidate identity. For enhancer work, use a unique alpha/candidate suffix consistent with the existing explicit artifact naming unless a later repository decision changes the scheme.
- **Artifact naming rule**: Candidate name must match code version and CI/package names; do not reuse an exact artifact/candidate identity across Active tasks.

## Runtime / deployment

- **Supported runtime/OS/platform**: Current enhancer: arm64 iOS 17.0+ inside official ChatGPT iOS app. Legacy app project also targets iPhoneOS 17.0+.
- **Deployment target(s)**: Enhancer compiler target `arm64-apple-ios17.0`; legacy Xcode target `IPHONEOS_DEPLOYMENT_TARGET = 17.0`.
- **Environment/configuration sources**: Enhancer runtime target validation uses official app bundle `com.openai.chat`; authentication/account request context is captured only in memory from the host app's own requests. No server-side deployment environment is part of this repository.

## Documentation evidence

- Branch inventory: GitHub branches API, scanned 2026-08-25.
- Current enhancer architecture/purpose: `ChatGPTEnhancer/README.md`, `ChatGPTEnhancer/ARCHITECTURE.md` on `feat/chatgpt-enhancer-v0.1`.
- Current enhancer build/runtime target: `ChatGPTEnhancer/build.sh`.
- Enhancer alpha39 CI/artifacts: Actions run `32841238704`.
- Enhancer alpha40 conversation-recognition CI/artifacts: Actions run `32850463066`; Draft PR #2 from `feat/conversation-recognition` to `feat/chatgpt-enhancer-v0.1`.
- Legacy app build/version: `.github/workflows/build-ipa.yml`, `GPTWebKit.xcodeproj/project.pbxproj` on `feat/0.2-native-recovery-exporter`.
- Repository default `main` before governance installation contained only `README.md` and `占位文件.txt`; therefore default-branch presence alone is not evidence of the accepted product baseline.

## Auto-refresh rule

Update this file proactively when project purpose, language/framework, build/test commands, version scheme, deployment/runtime, repository structure, or major state ownership changes.
