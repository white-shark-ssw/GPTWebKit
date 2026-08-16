# GPTWebKit

GPTWebKit is an iOS-focused ChatGPT web client built around `WKWebView`, with native bridges for capabilities that are awkward or restricted in mobile browsers.

Initial goals:

- Keep the normal ChatGPT web experience and account/session flow.
- Allow native document picking without an app-side extension whitelist.
- Allow picking both photos and videos from the iOS photo library.
- Improve stability and responsiveness in very long conversations.
- Detect and recover from WebKit content-process termination / blank-page failures.
- Export conversations to Markdown, including a future path for exporting directly from conversation history without opening the chat first.
- Build an unsigned device IPA in GitHub Actions for development and sideloading workflows.

> This is an independent client project and is not affiliated with or endorsed by OpenAI.
