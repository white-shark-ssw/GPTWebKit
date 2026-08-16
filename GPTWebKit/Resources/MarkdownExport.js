(() => {
  'use strict';
  if (window.GPTWebKitMarkdown) return;

  const cleanText = (node) => (node?.innerText || node?.textContent || '').replace(/\n{3,}/g, '\n\n').trim();
  const roleOf = (node, index) => node.getAttribute('data-message-author-role') || node.querySelector?.('[data-message-author-role]')?.getAttribute('data-message-author-role') || (index % 2 === 0 ? 'user' : 'assistant');
  const titleOf = () => document.title.replace(/\s*[-–|]\s*ChatGPT.*$/i, '').trim() || document.querySelector('header h1')?.textContent?.trim() || 'ChatGPT Conversation';
  const currentConversation = () => {
    const longConversation = window.GPTWebKitLongConversation;
    const tracked = longConversation?.getAllMessageNodes?.() || [];
    const nodes = tracked.length ? tracked : Array.from(document.querySelectorAll('main [data-message-author-role], main [data-testid^="conversation-turn-"]')).filter((node, index, all) => !all.some((other, i) => i !== index && other.contains(node)));
    const body = nodes.map((node, index) => `## ${roleOf(node, index) === 'user' ? 'User' : 'Assistant'}\n\n${cleanText(node)}`).join('\n\n---\n\n');
    return { title: titleOf(), markdown: `# ${titleOf()}\n\n${body}\n`, count: nodes.length };
  };

  const exportCurrent = () => {
    const result = currentConversation();
    if (!result.count) {
      alert('当前页面没有可导出的对话内容。');
      return;
    }
    try {
      if (window.webkit?.messageHandlers?.markdownExport) {
        window.webkit.messageHandlers.markdownExport.postMessage(result);
        return;
      }
    } catch (_) {}
    const blob = new Blob([result.markdown], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${result.title.replace(/[\\/:*?"<>|]/g, '_')}.md`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  const installButton = () => {
    if (!document.body || document.getElementById('gptwebkit-md-button')) return;
    const button = document.createElement('button');
    button.id = 'gptwebkit-md-button';
    button.textContent = 'MD';
    button.title = '导出当前对话为 Markdown';
    button.style.cssText = 'position:fixed;right:4px;top:calc(48% + 48px);z-index:2147483000;width:32px;height:42px;border:0;border-radius:12px 0 0 12px;background:rgba(0,0,0,.42);color:#fff;font:700 11px -apple-system,BlinkMacSystemFont,sans-serif;opacity:.55;';
    button.addEventListener('click', exportCurrent);
    document.body.appendChild(button);
  };

  window.GPTWebKitMarkdown = { currentConversation, exportCurrent, installButton };
  const start = () => {
    installButton();
    new MutationObserver(installButton).observe(document.documentElement, { childList: true, subtree: true });
  };
  if (document.body) start(); else addEventListener('DOMContentLoaded', start, { once: true });
})();
