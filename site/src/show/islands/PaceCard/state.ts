import { useMemo, useState } from 'react';

import { projectPace } from 'Helpers';

import type { PaceCardState, WindowOption } from './types';

export const WINDOW_OPTIONS: WindowOption[] = [
  { hours: 5, id: 'session', label: 'Session · 5 h' },
  { hours: 168, id: 'week', label: 'Week · 7 d' },
];

const hoursFor = (id: string) =>
  WINDOW_OPTIONS.find(option => option.id === id)?.hours ?? 5;

export const usePaceCard = (): PaceCardState => {
  const [used, onUsed] = useState(40);
  const [elapsed, onElapsed] = useState(50);
  const [windowId, onWindow] = useState('session');

  const result = useMemo(
    () =>
      projectPace({
        elapsedFraction: elapsed / 100,
        now: new Date(),
        usedPercent: used,
        windowHours: hoursFor(windowId),
      }),
    [elapsed, used, windowId]
  );

  return {
    elapsed,
    onElapsed,
    onUsed,
    onWindow,
    projected: result.projectedPercent,
    text: result.text,
    used,
    warn: result.warn,
    windowId,
  };
};
