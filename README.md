# GPTWebKit / ChatGPT Markdown

An iOS-native utility for browsing a signed-in ChatGPT account and exporting a selected conversation to Markdown.

Current 0.3 goals:

- Native UIKit UI only for normal use.
- Projects are shown above recent conversations, directly below native search.
- Open a project to browse all conversations in that project.
- Tap a conversation to confirm export, then rename the Markdown file.
- Long-press a conversation to skip the first confirmation and go directly to rename/export.
- Fetch conversation JSON directly by conversation ID; never render the selected conversation page.
- Keep a small native catalog cache so the app can show the last synced project/conversation list immediately on launch.
- WKWebView exists only to establish/reuse ChatGPT login state. It is not used as the product UI after login.

The 0.2 web-client features (chat UI, long-conversation rebase, native/web sidebars, upload/download bridges, web recovery UI) have been removed from the 0.3 target.

> This is an independent utility and is not affiliated with or endorsed by OpenAI. It uses undocumented ChatGPT web endpoints that may change.
