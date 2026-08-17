(() => {
  'use strict';
  if (window.__GPTWebKitUIEnhancements) return;
  window.__GPTWebKitUIEnhancements = true;

  let uploadResumeTimer = 0;
  let sidebarInterceptUntil = 0;
  let sidebarFetchBusy = false;
  let sidebarHydrating = false;

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
    if (button.matches('button[data-testid="open-sidebar-button"], button[data-testid*="sidebar" i], button[aria-label*="sidebar" i], button[title*="sidebar" i]')) return button;
    const rect = button.getBoundingClientRect();
    if (rect.top > 120 || rect.left > innerWidth * 0.32) return null;
    const label = `${button.getAttribute('aria-label') || ''} ${button.getAttribute('title') || ''} ${button.getAttribute('data-testid') || ''} ${button.textContent || ''}`;
    return /侧边栏|侧栏|打开菜单|open menu|menu/i.test(label) ? button : null;
  };

  const normalizeSidebarItems = (data) => {
    const raw = Array.isArray(data?.items) ? data.items : (Array.isArray(data?.conversations) ? data.conversations : (Array.isArray(data?.data?.items) ? data.data.items : (Array.isArray(data) ? data : [])));
    return raw.map((item) => {
      const source = item?.conversation || item?.chat || item;
      return {
        id: String(source?.id || source?.conversation_id || source?.conversationId || item?.id || item?.conversation_id || item?.conversationId || '').trim(),
        title: String(source?.title || source?.name || item?.title || item?.name || '新对话').trim() || '新对话',
        updatedAt: Number(source?.update_time || source?.updated_at || source?.create_time || item?.update_time || item?.updated_at || item?.create_time || 0) || 0
      };
    }).filter((item) => item.id).slice(0, 60);
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

  const installHydrateStyle = () => {
    if (document.getElementById('gptwebkit-sidebar-hydrate-style')) return;
    const style = document.createElement('style');
    style.id = 'gptwebkit-sidebar-hydrate-style';
    style.textContent = `html.gptwebkit-sidebar-hydrating aside, html.gptwebkit-sidebar-hydrating [data-testid*="sidebar" i] { opacity:0!important; pointer-events:none!important; transition:none!important; animation:none!important; }`;
    (document.head || document.documentElement).appendChild(style);
  };

  const hydrateFromOriginalSidebar = async () => {
    const existing = sidebarDOMItems();
    if (existing.length) return existing;
    if (sidebarHydrating) return [];
    const toggle = originalSidebarToggle();
    if (!(toggle instanceof HTMLElement)) return [];

    sidebarHydrating = true;
    installHydrateStyle();
    document.documentElement.classList.add('gptwebkit-sidebar-hydrating');
    let opened = false;
    try {
      toggle.click();
      opened = true;
      const started = performance.now();
      while (performance.now() - started < 950) {
        await new Promise((resolve) => setTimeout(resolve, 50));
        const items = sidebarDOMItems();
        if (items.length) return items;
      }
      return [];
    } catch (_) {
      return [];
    } finally {
      if (opened) {
        try {
          const close = document.querySelector('button[data-testid="close-sidebar-button"], button[aria-label*="close sidebar" i], button[title*="close sidebar" i]');
          if (close instanceof HTMLElement) close.click();
          else if (toggle.isConnected) toggle.click();
          else document.dispatchEvent(new KeyboardEvent('keydown', { key:'Escape', code:'Escape', bubbles:true }));
        } catch (_) {}
      }
      document.documentElement.classList.remove('gptwebkit-sidebar-hydrating');
      sidebarHydrating = false;
    }
  };

  const fetchSidebarItems = async () => {
    const proxy = window.GPTWebKitTailProxy;
    const previous = proxy?.getSettings?.() || null;
    const restoreOptimize = previous?.optimizeSidebar === true;
    if (restoreOptimize) proxy?.updateSettings?.({ optimizeSidebar:false });
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 650);
    try {
      const response = await fetch('/backend-api/conversations?offset=0&limit=28&order=updated&is_archived=false&is_starred=false', {
        method:'GET', credentials:'include', cache:'no-store', signal:controller.signal
      });
      if (!response.ok) return [];
      return normalizeSidebarItems(await response.json());
    } catch (_) {
      return [];
    } finally {
      clearTimeout(timeout);
      if (restoreOptimize) proxy?.updateSettings?.({ optimizeSidebar:true });
    }
  };

  const firstNonEmpty = async (...promises) => new Promise((resolve) => {
    let pending = promises.length;
    let settled = false;
    const finish = (items) => {
      if (settled) return;
      if (Array.isArray(items) && items.length) { settled = true; resolve(items); return; }
      pending--;
      if (pending <= 0) { settled = true; resolve([]); }
    };
    for (const promise of promises) Promise.resolve(promise).then(finish, () => finish([]));
  });

  const pushSidebarData = async () => {
    const handler = window.webkit?.messageHandlers?.sidebarData;
    if (!handler || sidebarFetchBusy || document.visibilityState !== 'visible') return false;
    sidebarFetchBusy = true;
    try {
      let items = sidebarDOMItems();
      if (!items.length) items = await firstNonEmpty(fetchSidebarItems(), hydrateFromOriginalSidebar());
      if (!items.length) return false;
      handler.postMessage({ items, at:Date.now() });
      return true;
    } catch (_) {
      return false;
    } finally {
      sidebarFetchBusy = false;
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
    setTimeout(pushSidebarData, 420);

    document.addEventListener('touchstart', suspendForUploadMenu, { capture:true, passive:true });
    document.addEventListener('pointerdown', (event) => {
      if (interceptSidebar(event)) return;
      suspendForUploadMenu(event);
    }, true);

    document.addEventListener('click', (event) => {
      const sidebar = sidebarButtonForTarget(event.target);
      if (performance.now() >= sidebarInterceptUntil && !sidebar) return;
      const handler = window.webkit?.messageHandlers?.nativeSidebar;
      if (!handler || !sidebar) return;
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
    }, true);

    window.addEventListener('popstate', () => setTimeout(pushSidebarData, 120));
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') setTimeout(pushSidebarData, 180);
    });
  };

  window.GPTWebKitNativeUI = { pushSidebarData, fetchSidebarItems, hydrateFromOriginalSidebar };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once:true });
  else start();
})();