import fs from 'fs';
import path from 'path';

export default async function (pi) {
  const agentDir = path.join(process.env.HOME || '/home/vscode', '.pi', 'agent');
  const modelsPath = path.join(agentDir, 'models.json');
  const authPath = path.join(agentDir, 'auth.json');

  if (!fs.existsSync(modelsPath)) return;

  let modelsConfig;
  try {
    modelsConfig = JSON.parse(fs.readFileSync(modelsPath, 'utf8'));
  } catch {
    return;
  }

  let authConfig = {};
  try {
    if (fs.existsSync(authPath)) {
      authConfig = JSON.parse(fs.readFileSync(authPath, 'utf8'));
    }
  } catch {}

  const providers = modelsConfig.providers || {};

  for (const [providerId, provider] of Object.entries(providers)) {
    // Если в models.json уже задан явный список models, не перезаписываем его
    if (!provider.baseUrl || (Array.isArray(provider.models) && provider.models.length > 0)) {
      continue;
    }

    const apiKey = authConfig[providerId]?.key || provider.apiKey || 'dummy';
    const baseUrl = provider.baseUrl.replace(/\/+$/, '');

    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 2000);

      const res = await fetch(`${baseUrl}/models`, {
        headers: apiKey && apiKey !== 'dummy' ? { Authorization: `Bearer ${apiKey}` } : {},
        signal: controller.signal
      });
      clearTimeout(timeout);

      if (!res.ok) continue;

      const body = await res.json();
      const items = Array.isArray(body.data) ? body.data : Array.isArray(body) ? body : [];
      if (items.length === 0) continue;

      const dynamicModels = items.map((m) => {
        const id = typeof m === 'string' ? m : m.id;
        const lower = id.toLowerCase();
        const hasReasoning =
          lower.includes('thinking') ||
          lower.includes('reasoning') ||
          lower.includes('high') ||
          lower.includes('argon') ||
          lower.includes('r1') ||
          lower.includes('o1') ||
          lower.includes('o3');

        return {
          id,
          name: m.name || id,
          reasoning: hasReasoning,
          contextWindow: m.context_length || m.contextWindow || 1000000,
          maxTokens: m.max_tokens || m.maxTokens || 64000,
          input: ['text', 'image'],
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
        };
      });

      pi.registerProvider(providerId, {
        baseUrl,
        api: provider.api || 'openai-completions',
        apiKey,
        models: dynamicModels
      });
    } catch {
      // Игнорируем сетевые сбои, чтобы не блокировать запуск Pi при оффлайн-эндпоинте
    }
  }
}
