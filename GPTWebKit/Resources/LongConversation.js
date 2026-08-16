(() => {
  'use strict';
  if (window.__gptWebKitLongConversation) return;
  window.__gptWebKitLongConversation = true;

  const settings = { minMessages: 14, overscan: 3, keepRecent: 4 };
  const state = { records: new Map(), ticking: false };

  const getMessages = () => Array.from(document.querySelectorAll('main [data-message-author-role], main [data-testid^="conversation-turn-"], main article')).filter((node, index, all) => !all.some((other, i) => i !== index && other.contains(node)));
  const scrollRoot = () => {
    let node = document.scrollingElement;
    for (const candidate of document.querySelectorAll('main, main *')) {
      const style = getComputedStyle(candidate);
      if (/(auto|scroll|overlay)/.test(style.overflowY) && candidate.scrollHeight > candidate.clientHeight * 1.2) node = candidate;
    }
    return node;
  };

  const restore = (record) => {
    if (!record.placeholder?.isConnected || !record.node) return;
    record.placeholder.replaceWith(record.node);
    record.placeholder = null;
  };

  const virtualize = (record) => {
    if (!record.node?.isConnected || record.placeholder) return;
    const rect = record.node.getBoundingClientRect();
    if (rect.height < 1) return;
    const placeholder = document.createElement('div');
    placeholder.dataset.gptwebkitPlaceholder = '1';
    placeholder.style.height = `${Math.ceil(rect.height)}px`;
    placeholder.style.minHeight = '1px';
    placeholder.style.contain = 'layout style paint';
    placeholder.addEventListener('click', () => restore(record), { once: true });
    record.node.replaceWith(placeholder);
    record.placeholder = placeholder;
  };

  const update = () => {
    state.ticking = false;
    const messages = getMessages();
    if (messages.length < settings.minMessages) return;
    messages.forEach((node) => { if (!state.records.has(node)) state.records.set(node, { node, placeholder: null }); });

    const root = scrollRoot();
    const viewportTop = root === document.scrollingElement ? 0 : root.getBoundingClientRect().top;
    const viewportBottom = root === document.scrollingElement ? innerHeight : root.getBoundingClientRect().bottom;
    const recentStart = Math.max(0, messages.length - settings.keepRecent);
    const visibleIndexes = [];

    messages.forEach((node, index) => {
      const record = state.records.get(node);
      const target = record.placeholder || node;
      const rect = target.getBoundingClientRect();
      if (rect.bottom >= viewportTop && rect.top <= viewportBottom) visibleIndexes.push(index);
    });

    const firstVisible = visibleIndexes.length ? Math.min(...visibleIndexes) : recentStart;
    const lastVisible = visibleIndexes.length ? Math.max(...visibleIndexes) : messages.length - 1;
    const keepStart = Math.max(0, firstVisible - settings.overscan);
    const keepEnd = Math.min(messages.length - 1, lastVisible + settings.overscan);

    messages.forEach((node, index) => {
      const record = state.records.get(node);
      const keep = (index >= keepStart && index <= keepEnd) || index >= recentStart;
      if (keep) restore(record); else virtualize(record);
    });
  };

  const schedule = () => {
    if (state.ticking) return;
    state.ticking = true;
    requestAnimationFrame(update);
  };

  addEventListener('scroll', schedule, true);
  addEventListener('resize', schedule, { passive: true });
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  schedule();
})();
