import type { DemoAccount, MetricOption } from './types';

export const DEMO_ACCOUNTS: DemoAccount[] = [
  {
    color: '#E58A00',
    cost: null,
    from: '~/.claude',
    id: 'work',
    label: 'Work',
    limit: 64,
    limitNote: 'Current session · resets in 2h 01m',
    provider: 'Claude Code',
    tokens: '18.4M',
    week: [0.42, 0.65, 0.38, 0.81, 0.57, 0.22, 0.74],
    windows: [
      {
        note: 'Resets in 2h 01m · limit around 18:40',
        title: 'Current session',
        used: 64,
      },
      { note: 'Resets in 5d 14h · on track', title: 'This week', used: 14 },
    ],
  },
  {
    color: '#3B82F6',
    cost: null,
    from: '~/.claude-personal',
    id: 'personal',
    label: 'Personal',
    limit: 11,
    limitNote: 'This week · resets in 4d 13h',
    provider: 'Claude Code',
    tokens: '3.1M',
    week: [0.12, 0.08, 0.3, 0.18, 0.44, 0.61, 0.2],
    windows: [
      { note: 'Resets in 3h 21m · on track', title: 'Current session', used: 2 },
      { note: 'Resets in 4d 13h · on track', title: 'This week', used: 11 },
    ],
  },
  {
    color: '#14B8A6',
    cost: null,
    from: '~/.codex',
    id: 'codex',
    label: 'Codex',
    limit: 27,
    limitNote: 'Weekly limit · resets in 2d 06h',
    provider: 'Codex',
    tokens: '6.7M',
    week: [0.3, 0.52, 0.47, 0.2, 0.66, 0.1, 0.35],
    windows: [{ note: 'Resets in 2d 06h · on track', title: 'Weekly limit', used: 27 }],
  },
  {
    color: '#8B5CF6',
    cost: '$4.82',
    from: 'Admin key',
    id: 'api',
    label: 'Team API',
    limit: null,
    limitNote: '',
    provider: 'Anthropic API',
    tokens: '2.2M',
    week: [0.55, 0.6, 0.48, 0.7, 0.52, 0.15, 0.1],
    windows: [],
  },
];

export const METRIC_OPTIONS: MetricOption[] = [
  { id: 'auto', label: 'Auto' },
  { id: 'tokens', label: 'Tokens' },
  { id: 'limits', label: 'Limits' },
  { id: 'cost', label: 'Cost' },
];

export const WEEKDAYS = ['Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed'];
