import fs from 'fs';
import path from 'path';
import { execFileSync } from 'child_process';

export default async function (pi) {
  const agentDir = path.join(process.env.HOME || '/home/vscode', '.pi', 'agent');
  const cachePath = path.join(agentDir, 'ai-providers.json');

  let rawData = '';
  if (fs.existsSync(cachePath)) {
    try {
      rawData = fs.readFileSync(cachePath, 'utf8');
    } catch {}
  }

  if (!rawData && process.env.OP_SERVICE_ACCOUNT_TOKEN) {
    try {
      rawData = execFileSync('op', ['item', 'get', 'AI-Providers-API', '--vault', 'Dev', '--format', 'json'], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
        timeout: 5000
      });
      fs.writeFileSync(cachePath, rawData, { mode: 0o600 });
    } catch {}
  }

  if (!rawData) return;

  let item;
  try {
    item = JSON.parse(rawData);
  } catch {
    return;
  }

  const sectionsById = {};
  for (const s of (item.sections || [])) {
    if (s.id && s.label) sectionsById[s.id] = s.label;
  }

  const providers = {};
  for (const f of (item.fields || [])) {
    if (!f.section || !f.section.id) continue;
    const sectionLabel = f.section.label || sectionsById[f.section.id];
    if (!sectionLabel) continue;

    const providerId = sectionLabel.toLowerCase().trim();
    if (!providers[providerId]) {
      providers[providerId] = {
        id: providerId,
        name: sectionLabel,
        api: '',
        url: '',
        key: ''
      };
    }

    const label = (f.label || '').toLowerCase();
    if (label === 'text') {
      providers[providerId].api = (f.value || '').trim();
    } else if (label === 'url') {
      providers[providerId].url = (f.value || '').trim();
    } else if (label === 'password') {
      providers[providerId].key = (f.value || '').trim();
    }
  }

  for (const [providerId, prov] of Object.entries(providers)) {
    // Поддерживаем только тип openai-completions
    if (prov.api !== 'openai-completions' || !prov.url) continue;

    let baseUrl = prov.url.replace(/\/+$/, '');
    try {
      const parsed = new URL(baseUrl);
      if (parsed.hostname === '127.0.0.1' || parsed.hostname === 'localhost') {
        parsed.hostname = 'host.docker.internal';
        baseUrl = parsed.toString().replace(/\/+$/, '');
      }
    } catch {}

    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 2500);

      const res = await fetch(`${baseUrl}/models`, {
        headers: prov.key ? { Authorization: `Bearer ${prov.key}` } : {},
        signal: controller.signal
      });
      clearTimeout(timeout);

      if (!res.ok) continue;

      const body = await res.json();
      const items = Array.isArray(body.data) ? body.data : Array.isArray(body) ? body : [];
      if (items.length === 0) continue;

      const models = items.map((m) => {
        const rawId = typeof m === 'string' ? m : m.id;
        const modelId = String(rawId).toLowerCase();
        const hasReasoning =
          modelId.includes('thinking') ||
          modelId.includes('reasoning') ||
          modelId.includes('high') ||
          modelId.includes('argon') ||
          modelId.includes('r1') ||
          modelId.includes('o1') ||
          modelId.includes('o3');

        return {
          id: modelId,
          name: modelId,
          reasoning: hasReasoning,
          contextWindow: m.context_length || m.contextWindow || 1000000,
          maxTokens: m.max_tokens || m.maxTokens || (hasReasoning ? 64000 : 16384),
          input: ['text', 'image'],
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
        };
      });

      pi.registerProvider(providerId, {
        baseUrl,
        api: 'openai-completions',
        apiKey: prov.key || 'dummy',
        models
      });
    } catch {
      // Игнорируем недоступные эндпоинты
    }
  }
}
