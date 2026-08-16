(() => {
  'use strict';
  if (window.GPTWebKitLongConversation) return;

  const settings = { minMessages: 14, overscan: 3, keepRecent: 4 };
  const state = { records: [], knownNodes: new WeakSet(), ticking: false, suspended: false, url: location.href };

  const discoverMessages = () => {
    const nodes = Array.from(document.querySelectorAll('main [data-message-author-role], main [data-testid^="conversation-turn-"], main article')).filter((node, index, all) => !all.some((other, i) => i !== index && other.contains(node)));
    for (const node of nodes) {
      if (state.knownNodes.has(node)) continue;
      state.knownNodes.add(node);
      state.records.push({ node, placeholder: null });
    }
    state.records = state.records.filter((record) => record.node?.isConnected || record.placeholder?.isConnected);
  };

  const scrollRoot = () => {
    let root = document.scrollingElement;
    for (const candidate of document.querySelectorAll('main, main *')) {
      const style = getComputedStyle(candidate);
      if (/(auto|scroll|overlay)/.test(style.overflowY) && candidate.scrollHeight > candidate.clientHeight * 1.2) root = candidate;
    }
    return root;
  };

  const restore = (record) => {
    if (!record.placeholder?.isConnected || !record.node) return;
    record.placeholder.replaceWith(record.node);
    record.placeholder = null;
  };

  const restoreAll = () => {
    state.suspended = true;
    state.records.forEach(restore);
    requestAnimationFrame(() => { state.suspended = false; schedule(); });
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
    placeholder.addEventListener('click', () => { restore(record); schedule(); }, { once: true });
    record.node.replaceWith(placeholder);
    record.placeholder = placeholder;
  };

  const resetForRouteChange = () => {
    if (state.url === location.href) return;
    state.url = location.href;
    state.records = [];
    state.knownNodes = new WeakSet();
  };

  const update = () => {
    state.ticking = false;
    if (state.suspended) return;
    resetForRouteChange();
    discoverMessages();
    const records = state.records;
    if (records.length < settings.minMessages) return;

    const root = scrollRoot();
    const viewportTop = root === document.scrollingElement ? 0 : root.getBoundingClientRect().top;
    const viewportBottom = root === document.scrollingElement ? innerHeight : root.getBoundingClientRect().bottom;
    const recentStart = Math.max(0, records.length - settings.keepRecent);
    const visibleIndexes = [];

    records.forEach((record, index) => {
      const target = record.placeholder || record.node;
      if (!target?.isConnected) return;
      const rect = target.getBoundingClientRect();
      if (rect.bottom >= viewportTop && rect.top <= viewportBottom) visibleIndexes.push(index);
    });

    const firstVisible = visibleIndexes.length ? Math.min(...visibleIndexes) : recentStart;
    const lastVisible = visibleIndexes.length ? Math.max(...visibleIndexes) : records.length - 1;
    const keepStart = Math.max(0, firstVisible - settings.overscan);
    const keepEnd = Math.min(records.length - 1, lastVisible + settings.overscan);

    records.forEach((record, index) => {
      const keep = (index >= keepStart && index <= keepEnd) || index >= recentStart;
      if (keep) restore(record); else virtualize(record);
    });
  };

  const schedule = () => {
    if (state.ticking) return;
    state.ticking = true;
    requestAnimationFrame(update);
  };

  window.GPTWebKitLongConversation = {
    restoreAll,
    getAllMessageNodes: () => state.records.map((record) => record.node).filter(Boolean),
    schedule
  };

  addEventListener('scroll', schedule, true);
  addEventListener('resize', schedule, { passive: true });
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  schedule();
})();
