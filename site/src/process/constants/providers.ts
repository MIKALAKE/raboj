import type { Provider } from './types';

export const PROVIDERS: Provider[] = [
  { beta: false, name: 'Claude Code', source: 'local' },
  { beta: false, name: 'Codex', source: 'local' },
  { beta: true, name: 'Gemini CLI', source: 'local' },
  { beta: false, name: 'Anthropic API', source: 'api' },
  { beta: false, name: 'OpenAI API', source: 'api' },
  { beta: true, name: 'xAI', source: 'api' },
  { beta: true, name: 'GitHub Copilot', source: 'api' },
  { beta: true, name: 'Cursor Teams', source: 'api' },
  { beta: true, name: 'OpenRouter', source: 'api' },
  { beta: true, name: 'DeepSeek', source: 'api' },
];
