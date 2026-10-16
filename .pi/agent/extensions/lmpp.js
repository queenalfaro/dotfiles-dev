import fs from 'fs';
import path from 'path';

export default async function (pi) {
  const baseUrl = 'http://host.docker.internal:8317/v1';
  let apiKey = '';
  try {
    const authPath = path.join(process.env.HOME, '.pi', 'agent', 'auth.json');
    if (fs.existsSync(authPath)) {
      const auth = JSON.parse(fs.readFileSync(authPath, 'utf8'));
      apiKey = auth.lmpp?.key || auth.lmpp || '';
    }
  } catch (e) {}

  let models = [];
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 1500);
    const res = await fetch(`${baseUrl}/models`, {
      headers: apiKey ? { Authorization: `Bearer ${apiKey}` } : {},
      signal: controller.signal
    });
    clearTimeout(timeout);
    if (res.ok) {
      const json = await res.json();
      if (Array.isArray(json.data)) {
        models = json.data.map(m => ({
          id: m.id,
          name: m.id,
          reasoning: m.id.includes('thinking') || m.id.includes('high') || m.id.includes('argon'),
          contextWindow: 1000000,
          maxTokens: 64000,
          input: ['text', 'image'],
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
        }));
      }
    }
  } catch (e) {}

  if (models.length === 0) {
    models = [
      {
        id: 'gemini-3.8-flash-high',
        name: 'gemini-3.8-flash-high',
        reasoning: true,
        contextWindow: 1000000,
        maxTokens: 64000,
        input: ['text', 'image'],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
      }
    ];
  }

  pi.registerProvider('lmpp', {
    baseUrl,
    api: 'openai-completions',
    apiKey: apiKey || 'dummy',
    models
  });
}
