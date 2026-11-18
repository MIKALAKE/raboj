import { useCallback, useEffect, useState } from 'react';

import type { DemoMetric } from 'Constants/types';
import { DEMO_ACCOUNTS, HINT_DISMISSED_EVENT } from 'Constants';

import type { PopoverState, Selection } from './types';

const SHORTCUT_KEYS = ['0', '1', '2', '3', '4'];

const selectionForKey = (key: string): Selection | null => {
  const index = SHORTCUT_KEYS.indexOf(key);
  if (index < 0) return null;
  return index === 0 ? 'all' : (DEMO_ACCOUNTS[index - 1]?.id ?? null);
};

export const useRabojPopover = (hint: boolean): PopoverState => {
  const [selection, setSelection] = useState<Selection>('all');
  const [metric, setMetric] = useState<DemoMetric>('auto');
  const [showHint, setShowHint] = useState(hint);

  const dismissHint = useCallback(() => {
    setShowHint(false);
    window.dispatchEvent(new Event(HINT_DISMISSED_EVENT));
  }, []);

  const select = useCallback(
    (next: Selection) => {
      setSelection(next);
      dismissHint();
    },
    [dismissHint]
  );

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if (!event.metaKey && !event.ctrlKey) return;
      const next = selectionForKey(event.key);
      if (!next) return;
      event.preventDefault();
      select(next);
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [select]);

  return { dismissHint, metric, select, selection, setMetric, showHint };
};
