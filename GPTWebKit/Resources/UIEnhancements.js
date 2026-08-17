(() => {
  'use strict';
  if (window.__GPTWebKitUIEnhancements) return;
  window.__GPTWebKitUIEnhancements = true;

  let uploadResumeTimer = 0;
  let sidebarInterceptUntil = 0;
  let sidebarFetchBusy = false;

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
    return raw.map((item) => ({
      id: String(item?.id || item?.conversation_id || '').trim(),
      title: String(item?.title || item?.name || '新对话').trim() || '新对话',
      updatedAt: Number(item?.update_time || item?.updated_at || item?.create_time || 0) || 0
    })).filter((item) => item.id).slice(0, 60);
  };

  const fetchSidebarItems = async () => {
    const proxy = window.GPTWebKitTailProxy;
    const previous = proxy?.getSettings?.() || null;
    const restoreOptimize = previous?.optimizeSidebar === true;
    if (restoreOptimize) proxy?.updateSettings?.({ optimizeSidebar:false });
    const urls = [
      '/backend-api/conversations?offset=0&limit=28&order=updated',
      '/backend-api/conversations?offset=0&limit=28&order=updated&is_archived=false',
      '/backend-api/conversations?offset=0&limit=28&order=updated&is_archived=false&is_starred=false'
    ];
    try {
      for (const url of urls) {
        try {
          const response = await fetch(url, { method:'GET', credentials:'include', cache:'no-store' });
          if (!response.ok) continue;
          const items = normalizeSidebarItems(await response.json());
          if (items.length) return items;
        } catch (_) {}
      }
      return [];
    } finally {
      if (restoreOptimize) proxy?.updateSettings?.({ optimizeSidebar:true });
    }
  };

  const pushSidebarData = async () => {
    const handler = window.webkit?.messageHandlers?.sidebarData;
    if (!handler || sidebarFetchBusy || document.visibilityState !== 'visible') return false;
    sidebarFetchBusy = true;
    try {
      const items = await fetchSidebarItems();
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
    setTimeout(pushSidebarData, 80);
    setTimeout(pushSidebarData, 1400);

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

    window.addEventListener('popstate', () => setTimeout(pushSidebarData, 160));
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') setTimeout(pushSidebarData, 220);
    });
  };

  window.GPTWebKitNativeUI = { pushSidebarData, fetchSidebarItems };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once:true });
  else start();
})();