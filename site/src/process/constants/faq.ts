import type { FaqItem } from './types';

export const FAQ: FaqItem[] = [
  {
    answer:
      'Răboj is a free, open source macOS menu bar app that shows your AI usage: Claude Code and Codex plan limits, tokens and cost for every account, plus API spend for Anthropic, OpenAI, xAI, GitHub Copilot, Cursor, OpenRouter and DeepSeek.',
    question: 'What is Răboj?',
  },
  {
    answer:
      'Yes. Add each Claude Code config folder (for example ~/.claude and ~/.claude-personal). Usage and limits are filed by the Claude account that made them, so logging in to another account inside a folder never mixes the two.',
    question: 'Can I track a work and a personal Claude account?',
  },
  {
    answer:
      'Token counts come from the logs on this Mac, so they only include Claude Code here. The session and weekly limits come straight from Claude Code’s status line, so with that set up they match /usage.',
    question: 'Why can the numbers differ from Claude’s /usage?',
  },
  {
    answer:
      'No. There is no Răboj server and no telemetry. Folder accounts are read locally; API accounts call only the provider you connected, and every request is listed in the Access Log.',
    question: 'Does Răboj send my data anywhere?',
  },
  {
    answer:
      'Run brew install mikalake/tap/raboj, or download the DMG from GitHub Releases. Răboj needs macOS 14 Sonoma or later and runs on Apple silicon and Intel.',
    question: 'How do I install it?',
  },
];
