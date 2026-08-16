(() => {
  'use strict';
  if (window.GPTWebKitMarkdown) return;

  const cleanText = (node) => (node?.innerText || node?.textContent || '').replace(/\n{3,}/g, '\n\n').trim();
  const roleOf = (node, index) => node.getAttribute('data-message-author-role') || node.querySelector?.('[data-message-author-role]')?.getAttribute('data-message-author-role') || (index % 2 === 0 ? 'user' : 'assistant');
  const currentConversation = () => {
    const longConversation = window.GPTWebKitLongConversation;
    longConversation?.restoreAll?.();
    const tracked = longConversation?.getAllMessageNodes?.() || [];
    const nodes = tracked.length ? tracked : Array.from(document.querySelectorAll('main [data-message-author-role], main [data-testid^="conversation-turn-"]')).filter((node, index, all) => !all.some((other, i) => i !== index && other.contains(node)));
    const title = document.title.replace(/\s*[-–|]\s*ChatGPT.*$/i, '').trim() || 'ChatGPT Conversation';
    const body = nodes.map((node, index) => `## ${roleOf(node, index) === 'user' ? 'User' : 'Assistant'}\n\n${cleanText(node)}`).join('\n\n---\n\n');
    return `# ${title}\n\n${body}\n`;
  };

  // Native bridge entry point. History-list export will plug in a non-DOM conversation source.
  window.GPTWebKitMarkdown = { currentConversation };
})();
