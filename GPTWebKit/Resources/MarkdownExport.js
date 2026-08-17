(() => {
  'use strict';
  if (window.GPTWebKitMarkdown) return;

  let exportBusy = false;
  const titleOfPage = () => document.title.replace(/\s*[-–|]\s*ChatGPT.*$/i, '').trim() || document.querySelector('header h1')?.textContent?.trim() || 'ChatGPT Conversation';
  const normalize = (text) => String(text || '').replace(/\r\n/g, '\n').replace(/[ \t]+\n/g, '\n').replace(/\n[ \t]+/g, '\n').replace(/\n{3,}/g, '\n\n').trim();

  const messageNodes = () => {
    const tracked = window.GPTWebKitLongConversation?.getAllMessageNodes?.() || [];
    if (tracked.length) return tracked;
    const turns = Array.from(document.querySelectorAll('main [data-testid^="conversation-turn-"]'));
    if (turns.length) return turns;
    return Array.from(document.querySelectorAll('main [data-message-author-role]')).filter((node) => !node.parentElement?.closest?.('[data-message-author-role]'));
  };

  const roleOfNode = (node, index) => node.getAttribute('data-message-author-role') || node.querySelector?.('[data-message-author-role]')?.getAttribute('data-message-author-role') || (index % 2 === 0 ? 'user' : 'assistant');
  const cleanClone = (node) => {
    const clone = node.cloneNode(true);
    clone.querySelectorAll('script,style,noscript,button,svg,[aria-hidden="true"],[data-testid*="copy" i],[data-testid*="feedback" i]').forEach((item) => item.remove());
    return clone;
  };
  const escapePipes = (text) => text.replace(/\|/g, '\\|').replace(/\n+/g, ' ').trim();
  const children = (node) => Array.from(node.childNodes).map(renderNode).join('');

  const renderTable = (table) => {
    const rows = Array.from(table.querySelectorAll('tr')).map((row) => Array.from(row.querySelectorAll(':scope > th, :scope > td')).map((cell) => escapePipes(normalize(children(cell))))).filter((row) => row.length);
    if (!rows.length) return '';
    const width = Math.max(...rows.map((row) => row.length));
    const pad = (row) => Array.from({ length: width }, (_, i) => row[i] || '');
    const header = pad(rows[0]);
    const body = rows.slice(1).map(pad);
    return `\n\n| ${header.join(' | ')} |\n| ${header.map(() => '---').join(' | ')} |${body.length ? `\n${body.map((row) => `| ${row.join(' | ')} |`).join('\n')}` : ''}\n\n`;
  };

  const renderList = (list) => {
    const ordered = list.tagName === 'OL';
    let index = Number(list.getAttribute('start') || 1);
    const lines = [];
    for (const li of Array.from(list.children).filter((item) => item.tagName === 'LI')) {
      const clone = li.cloneNode(true);
      clone.querySelectorAll(':scope > ul, :scope > ol').forEach((item) => item.remove());
      const prefix = ordered ? `${index++}. ` : '- ';
      const main = normalize(children(clone)).replace(/\n/g, '\n  ');
      lines.push(prefix + main);
      for (const nested of Array.from(li.children).filter((item) => item.tagName === 'UL' || item.tagName === 'OL')) {
        const nestedText = renderList(nested).trim().split('\n').map((line) => `  ${line}`).join('\n');
        if (nestedText) lines.push(nestedText);
      }
    }
    return `\n${lines.join('\n')}\n`;
  };

  const mathSource = (element) => {
    const annotation = element.querySelector?.('annotation[encoding="application/x-tex"]');
    return element.getAttribute?.('data-latex') || annotation?.textContent || '';
  };

  function renderNode(node) {
    if (!node) return '';
    if (node.nodeType === Node.TEXT_NODE) return node.nodeValue || '';
    if (node.nodeType !== Node.ELEMENT_NODE) return '';
    const el = node;
    const tag = el.tagName;
    if (tag === 'BR') return '\n';
    if (/^H[1-6]$/.test(tag)) return `\n\n${'#'.repeat(Number(tag[1]))} ${normalize(children(el))}\n\n`;
    if (tag === 'P') return `\n\n${children(el)}\n\n`;
    if (tag === 'STRONG' || tag === 'B') return `**${children(el)}**`;
    if (tag === 'EM' || tag === 'I') return `*${children(el)}*`;
    if (tag === 'DEL' || tag === 'S') return `~~${children(el)}~~`;
    if (tag === 'BLOCKQUOTE') return `\n\n${normalize(children(el)).split('\n').map((line) => `> ${line}`).join('\n')}\n\n`;
    if (tag === 'HR') return '\n\n---\n\n';
    if (tag === 'UL' || tag === 'OL') return renderList(el);
    if (tag === 'TABLE') return renderTable(el);
    if (tag === 'PRE') {
      const code = el.querySelector('code') || el;
      const language = code.getAttribute('data-language') || Array.from(code.classList || []).map((item) => item.match(/^language-(.+)$/)?.[1]).find(Boolean) || '';
      const value = (code.textContent || '').replace(/\n$/, '');
      const longest = Math.max(3, ...Array.from(value.matchAll(/`+/g), (match) => match[0].length + 1));
      const fence = '`'.repeat(longest);
      return `\n\n${fence}${language}\n${value}\n${fence}\n\n`;
    }
    if (tag === 'CODE') {
      const value = el.textContent || '';
      const fence = value.includes('`') ? '``' : '`';
      return `${fence}${value}${fence}`;
    }
    if (tag === 'A') {
      const href = el.getAttribute('href') || '';
      const text = normalize(children(el)) || href;
      if (!href || href.startsWith('javascript:')) return text;
      return `[${text}](${href})`;
    }
    if (tag === 'IMG') {
      const src = el.getAttribute('src') || '';
      if (!src) return '';
      return `![${el.getAttribute('alt') || ''}](${src})`;
    }
    if (tag === 'SUP') return children(el);
    if (tag === 'DETAILS') {
      const summary = el.querySelector(':scope > summary')?.textContent?.trim();
      const clone = el.cloneNode(true);
      clone.querySelector(':scope > summary')?.remove();
      const body = normalize(children(clone));
      return `\n\n${summary ? `**${summary}**\n\n` : ''}${body}\n\n`;
    }
    if (el.matches?.('.katex, .katex-display, [data-latex]')) {
      const tex = mathSource(el);
      if (tex) return el.matches('.katex-display') || el.closest('.katex-display') === el ? `\n\n$$\n${tex}\n$$\n\n` : `$${tex}$`;
    }
    return children(el);
  }

  const renderDOMMessage = (node, index) => {
    const clone = cleanClone(node);
    const content = clone.querySelector('.markdown, [class*="markdown"], [data-message-author-role]') || clone;
    const role = roleOfNode(node, index) === 'user' ? 'User' : 'Assistant';
    return `## ${role}\n\n${normalize(renderNode(content))}`;
  };

  const currentConversationFromDOM = () => {
    const nodes = messageNodes();
    const title = titleOfPage();
    const body = nodes.map(renderDOMMessage).filter((item) => item.trim()).join('\n\n---\n\n');
    return { title, markdown: `# ${title}\n\n${body}\n`, count: nodes.length, source: 'dom' };
  };

  const containerOf = (data) => {
    if (data?.mapping && typeof data.mapping === 'object') return data;
    if (data?.conversation?.mapping && typeof data.conversation.mapping === 'object') return data.conversation;
    return null;
  };

  const currentPath = (mapping, currentNode) => {
    const reversed = [];
    const visited = new Set();
    let id = currentNode;
    while (id && mapping[id] && !visited.has(id)) {
      visited.add(id);
      reversed.push(id);
      id = mapping[id]?.parent || null;
    }
    reversed.reverse();
    return reversed;
  };

  const partToText = (part) => {
    if (typeof part === 'string') return part;
    if (!part || typeof part !== 'object') return '';
    if (typeof part.text === 'string') return part.text;
    if (typeof part.content === 'string') return part.content;
    if (typeof part.transcript === 'string') return part.transcript;
    if (part.content_type === 'image_asset_pointer' || part.asset_pointer) return '[图片]';
    return '';
  };

  const messageText = (message) => {
    const content = message?.content || {};
    const parts = Array.isArray(content.parts) ? content.parts : [];
    let text = parts.map(partToText).filter(Boolean).join('\n');
    if (!text && typeof content.text === 'string') text = content.text;
    text = normalize(text);
    return text.replace(/cite[^]+/g, '').replace(/[^]+/g, '').trim();
  };

  const sourceEntries = (message) => {
    const metadata = message?.metadata || {};
    const candidates = [];
    if (Array.isArray(metadata.content_references)) candidates.push(...metadata.content_references);
    if (Array.isArray(metadata.citations)) candidates.push(...metadata.citations);
    const seen = new Set();
    const out = [];
    const scan = (value, depth = 0) => {
      if (!value || depth > 3) return;
      if (Array.isArray(value)) { value.forEach((item) => scan(item, depth + 1)); return; }
      if (typeof value !== 'object') return;
      const url = typeof value.url === 'string' && /^https?:\/\//i.test(value.url) ? value.url : '';
      const title = typeof value.title === 'string' ? value.title.trim() : '';
      if (url && !seen.has(url)) { seen.add(url); out.push({ title: title || url, url }); }
      for (const key of ['metadata', 'source', 'sources', 'attribution', 'items']) if (value[key]) scan(value[key], depth + 1);
    };
    candidates.forEach((item) => scan(item));
    return out;
  };

  const renderJSONMessage = (node) => {
    const message = node?.message;
    const role = message?.author?.role;
    if (role !== 'user' && role !== 'assistant') return '';
    const text = messageText(message);
    if (!text) return '';
    const heading = role === 'user' ? 'User' : 'Assistant';
    const sources = sourceEntries(message);
    const sourceText = sources.length ? `\n\n### Sources\n\n${sources.map((item) => `- [${item.title.replace(/\]/g, '\\]')}](${item.url})`).join('\n')}` : '';
    return `## ${heading}\n\n${text}${sourceText}`;
  };

  const decodeJWT = (token) => {
    try {
      const part = String(token || '').split('.')[1] || '';
      const base64 = part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=');
      return JSON.parse(decodeURIComponent(Array.from(atob(base64), (char) => `%${char.charCodeAt(0).toString(16).padStart(2, '0')}`).join('')));
    } catch (_) {
      return {};
    }
  };

  const accountIdFromSession = (session, accessToken) => {
    const claims = decodeJWT(accessToken);
    const auth = claims?.['https://api.openai.com/auth'] || claims?.['https://openai.com/auth'] || {};
    return String(session?.account?.id || session?.account_id || session?.user?.account_id || claims?.['https://api.openai.com/auth.chatgpt_account_id'] || claims?.['https://openai.com/auth.chatgpt_account_id'] || auth?.chatgpt_account_id || claims?.chatgpt_account_id || '').trim();
  };

  const fetchWithTimeout = async (url, init, timeoutMs, label) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      return await fetch(url, { ...init, signal: controller.signal });
    } catch (error) {
      if (error?.name === 'AbortError') throw new Error(`${label}超时`);
      throw error;
    } finally {
      clearTimeout(timer);
    }
  };

  const fetchFullConversationAuthenticated = async (id) => {
    const proxy = window.GPTWebKitTailProxy;
    const previous = proxy?.getSettings?.() || null;
    const target = `/backend-api/conversation/${encodeURIComponent(id)}`;
    try {
      if (proxy?.updateSettings) proxy.updateSettings({ enabled: false });
      const sessionResponse = await fetchWithTimeout('/api/auth/session', { method: 'GET', credentials: 'include', cache: 'no-store' }, 7000, '读取登录状态');
      if (!sessionResponse.ok) throw new Error(`读取登录状态失败 (${sessionResponse.status})`);
      let session = {};
      try { session = await sessionResponse.json(); } catch (_) { throw new Error('登录状态返回内容不是 JSON'); }
      const accessToken = String(session?.accessToken || session?.access_token || '');
      if (!accessToken) throw new Error('未取得网页访问令牌');
      const accountId = accountIdFromSession(session, accessToken);
      const headers = new Headers({ accept: 'application/json', 'x-openai-target-path': target, authorization: `Bearer ${accessToken}` });
      if (accountId) headers.set('chatgpt-account-id', accountId);
      const response = await fetchWithTimeout(target, { method: 'GET', credentials: 'include', cache: 'no-store', headers, referrer: location.href }, 75000, '读取完整会话');
      if (!response.ok) throw new Error(`读取完整会话失败 (${response.status})`);
      const type = response.headers.get('content-type') || '';
      if (!/json/i.test(type)) throw new Error('完整会话返回内容不是 JSON');
      return await response.json();
    } finally {
      if (proxy?.updateSettings && previous) proxy.updateSettings({ enabled: previous.enabled !== false });
    }
  };

  const fetchFullConversation = async (id) => {
    const proxy = window.GPTWebKitTailProxy;
    if (proxy?.fetchFullConversation) {
      try { return await proxy.fetchFullConversation(id); } catch (_) {}
    }
    return fetchFullConversationAuthenticated(id);
  };

  const fullConversation = async () => {
    const proxy = window.GPTWebKitTailProxy;
    const id = proxy?.currentConversationId?.() || location.pathname.match(/\/c\/([^/?#]+)/)?.[1] || '';
    if (!id) return currentConversationFromDOM();
    const data = await fetchFullConversation(id);
    const container = containerOf(data);
    if (!container?.mapping || !container?.current_node) throw new Error('完整会话结构无法识别');
    const path = currentPath(container.mapping, container.current_node);
    const rendered = path.map((nodeId) => renderJSONMessage(container.mapping[nodeId])).filter(Boolean);
    if (!rendered.length) throw new Error('完整会话中没有可导出的用户/助手消息');
    const title = normalize(container.title || data?.title || titleOfPage()) || 'ChatGPT Conversation';
    return { title, markdown: `# ${title}\n\n${rendered.join('\n\n---\n\n')}\n`, count: rendered.length, source: 'full-json', conversationId: id, currentNode: container.current_node };
  };

  const shareResult = (result) => {
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

  const exportCurrent = async () => {
    if (exportBusy) return;
    exportBusy = true;
    try {
      const result = await fullConversation();
      shareResult(result);
    } catch (error) {
      alert(`导出失败：${error?.message || error}`);
    } finally {
      setTimeout(() => { exportBusy = false; }, 1200);
    }
  };

  window.GPTWebKitMarkdown = { currentConversation: currentConversationFromDOM, fullConversation, exportCurrent };
})();
