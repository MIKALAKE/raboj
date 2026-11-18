import type { Entry, TotalLine } from './types';

export const ENTRIES: Entry[] = [
  {
    detail: 'Work and personal, several orgs. Each has a name and color.',
    label: 'Accounts per provider',
    qty: 'no limit',
  },
  {
    detail: 'The same windows as /usage, with reset time and pace.',
    label: 'Limit windows',
    qty: '5 h · 7 d',
  },
  {
    detail: 'Week chart, token split, models and projects.',
    label: 'Days of history',
    qty: '1 · 7 · 30',
  },
  {
    detail: 'All, then each account. ⌥-click the icon to cycle.',
    label: 'Shortcuts',
    qty: '⌘0 – ⌘9',
  },
];

export const TOTALS: TotalLine[] = [
  { label: 'Servers', value: '0' },
  { label: 'Telemetry events', value: '0' },
  { label: 'Messages read', value: '0' },
];
