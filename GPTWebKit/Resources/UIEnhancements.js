(() => {
  'use strict';
  if (window.__GPTWebKitUIEnhancements) return;
  window.__GPTWebKitUIEnhancements = true;

  let uploadResumeTimer = 0;
  let sidebarInterceptUntil = 0;
  let sidebarReadBusy = false;

  const removeLegacyOverlays = () => {
    document.getElementById('gptwebkit-inline-history')?.remove();
    document.getElementById('gptwebkit-conversation-limit')?.remove();
    document.getElementById('gptwebkit-ui-enhancements-style')?.remove();
  };

  const getLongConversation = () => window.GPTWebKitLongConversation;

  const composerUtilityButton = (target) => {
    const button = target?.closest?.('button');
    if (!(button instanceof HTMLElement)) return null;
    const prompt = document.querySelector('#prompt-textarea, textarea, [contenteditable="true"][data-placeholder]');
    const composer = prompt?.closest('form') || prompt?.parentElement?.parentElement;
    if (!composer?.contains(button)) return null;
    const label = `${button.getAttribute('aria-label') || ''} ${button.getAttribute('title') || ''} ${button.getAttribute('data-testid') || ''} ${button.textContent || ''}`;
    return /添加|附件|照片|文件|上传|attach|upload|photo|file|add/i.test(label) ? button : null;
  };

  const suspendForUploadMenu = (event) => {
    if (!event.isTrusted || !composerUtilityButton(event.target)) return;
    getLongConversation()?.suspend?.();
    if (uploadResumeTimer) clearTimeout(uploadResumeTimer);
    uploadResumeTimer = setTimeout(() => {
      uploadResumeTimer = 0;
      getLongConversation()?.resume?.();
    }, 900);
  };

  const sidebarButtonForTarget = (target) => {
    const button = target?.closest?.('button');
    if (!(button instanceof HTMLElement)) return null;
    if (button.matches('button[data-testid="open-sidebar-button"], button[data-testid="close-sidebar-button"], button[data-testid*="sidebar" i], button[aria-label*="sidebar" i], button[title*="sidebar" i]')) return button;
    const rect = button.getBoundingClientRect();
    if (rect.top > 120 || rect.left > innerWidth * 0.32) return null;
    const label = `${button.getAttribute('aria-label') || ''} ${button.getAttribute('title') || ''} ${button.getAttribute('data-testid') || ''} ${button.textContent || ''}`;
    return /侧边栏|侧栏|打开菜单|关闭菜单|open menu|close menu|sidebar/i.test(label) ? button : null;
  };

  const originalSidebarToggle = () => {
    const exact = document.querySelector('button[data-testid="open-sidebar-button"], button[data-testid="close-sidebar-button"], button[aria-label*="sidebar" i], button[title*="sidebar" i]');
    if (exact instanceof HTMLElement) return exact;
    for (const button of document.querySelectorAll('button')) {
      const rect = button.getBoundingClientRect();
      if (rect.top > 120 || rect.left > innerWidth * 0.32) continue;
      const label = `${button.getAttribute('aria-label') || ''} ${button.getAttribute('title') || ''} ${button.getAttribute('data-testid') || ''} ${button.textContent || ''}`;
      if (/侧边栏|侧栏|打开菜单|关闭菜单|open menu|close menu|sidebar/i.test(label)) return button;
    }
    return null;
  };

  const sidebarDOMItems = () => {
    const seen = new Set();
    const items = [];
    for (const anchor of document.querySelectorAll('a[href*="/c/"]')) {
      let url;
      try { url = new URL(anchor.getAttribute('href') || '', location.href); } catch (_) { continue; }
      const match = url.pathname.match(/^\/c\/([^/?#]+)/);
      const id = match?.[1] || '';
      if (!id || seen.has(id)) continue;
      let title = String(anchor.textContent || '').replace(/\s+/g, ' ').trim();
      if (!title) title = String(anchor.getAttribute('aria-label') || anchor.getAttribute('title') || '').trim();
      if (!title || title.length > 240) continue;
      seen.add(id);
      items.push({ id, title, updatedAt:0 });
      if (items.length >= 60) break;
    }
    return items;
  };

  const installHydrateStyle = () => {
    if (document.getElementById('gptwebkit-sidebar-hydrate-style')) return;
    const style = document.createElement('style');
    style.id = 'gptwebkit-sidebar-hydrate-style';
    style.textContent = `html.gptwebkit-sidebar-hydrating aside, html.gptwebkit-sidebar-hydrating [data-testid*="sidebar" i] { opacity:0!important; pointer-events:none!important; transition:none!important; animation:none!important; }`;
    (document.head || document.documentElement).appendChild(style);
  };

  const waitForSidebarItems = (timeout = 1300) => new Promise((resolve) => {
    let finished = false;
    let observer = null;
    let timer = 0;
    const finish = (items) => {
      if (finished) return;
      finished = true;
      observer?.disconnect();
      if (timer) clearTimeout(timer);
      resolve(Array.isArray(items) ? items : []);
    };
    const inspect = () => {
      const items = sidebarDOMItems();
      if (items.length) finish(items);
    };
    inspect();
    if (finished) return;
    observer = new MutationObserver(inspect);
    observer.observe(document.body || document.documentElement, { childList:true, subtree:true });
    timer = setTimeout(() => finish(sidebarDOMItems()), timeout);
  });

  const closeOriginalSidebar = (openedToggle) => {
    try {
      const close = document.querySelector('button[data-testid="close-sidebar-button"], button[aria-label*="close sidebar" i], button[title*="close sidebar" i], button[aria-label*="关闭侧边栏" i], button[title*="关闭侧边栏" i]');
      if (close instanceof HTMLElement) { close.click(); return; }
      if (openedToggle?.isConnected) { openedToggle.click(); return; }
      document.dispatchEvent(new KeyboardEvent('keydown', { key:'Escape', code:'Escape', bubbles:true }));
    } catch (_) {}
  };

  const hydrateFromOriginalSidebar = async () => {
    const existing = sidebarDOMItems();
    if (existing.length) return existing;
    const toggle = originalSidebarToggle();
    if (!(toggle instanceof HTMLElement)) return [];

    installHydrateStyle();
    document.documentElement.classList.add('gptwebkit-sidebar-hydrating');
    try {
      toggle.click();
      return await waitForSidebarItems();
    } catch (_) {
      return [];
    } finally {
      closeOriginalSidebar(toggle);
      document.documentElement.classList.remove('gptwebkit-sidebar-hydrating');
    }
  };

  const publishSidebarItems = (items) => {
    if (!Array.isArray(items) || !items.length) return false;
    const handler = window.webkit?.messageHandlers?.sidebarData;
    if (!handler) return false;
    try {
      handler.postMessage({ items, at:Date.now() });
      return true;
    } catch (_) {
      return false;
    }
  };

  const pushSidebarData = async () => {
    if (sidebarReadBusy || document.visibilityState !== 'visible') return false;
    sidebarReadBusy = true;
    try {
      let items = sidebarDOMItems();
      if (!items.length) items = await hydrateFromOriginalSidebar();
      return publishSidebarItems(items);
    } finally {
      sidebarReadBusy = false;
    }
  };

  const interceptSidebar = (event) => {
    const handler = window.webkit?.messageHandlers?.nativeSidebar;
    if (!handler || !event.isTrusted || !sidebarButtonForTarget(event.target)) return false;
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    sidebarInterceptUntil = performance.now() + 700;
    try { handler.postMessage({ href:location.href }); } catch (_) {}
    setTimeout(pushSidebarData, 0);
    return true;
  };

  const start = () => {
    removeLegacyOverlays();
    setTimeout(pushSidebarData, 180);
    setTimeout(pushSidebarData, 1200);

    document.addEventListener('touchstart', suspendForUploadMenu, { capture:true, passive:true });
    document.addEventListener('pointerdown', (event) => {
      if (interceptSidebar(event)) return;
      suspendForUploadMenu(event);
    }, true);

    document.addEventListener('click', (event) => {
      if (!event.isTrusted) return;
      const sidebar = sidebarButtonForTarget(event.target);
      if (performance.now() >= sidebarInterceptUntil && !sidebar) return;
      const handler = window.webkit?.messageHandlers?.nativeSidebar;
      if (!handler || !sidebar) return;
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
    }, true);

    window.addEventListener('popstate', () => setTimeout(pushSidebarData, 120));
    addEventListener('load', () => setTimeout(pushSidebarData, 80), { once:true });
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') setTimeout(pushSidebarData, 180);
    });
  };

  window.GPTWebKitNativeUI = { pushSidebarData, hydrateFromOriginalSidebar, sidebarDOMItems };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once:true });
  else start();
})();