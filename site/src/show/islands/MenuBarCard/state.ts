import { useCallback, useState } from 'react';

import type { MenuBarCardState, MenuBarMode, ModeOption } from './types';

export const MODE_OPTIONS: ModeOption[] = [
  {
    id: 'selection',
    label: 'Selected',
    note: 'Shows the account open in the popover. ⌘1 – ⌘4 change it.',
  },
  {
    id: 'pinned',
    label: 'Pinned',
    note: 'Several accounts side by side, each in its color. Click to pin or unpin.',
  },
  {
    id: 'icon',
    label: 'Icon only',
    note: 'Just the tally. The numbers stay one click away.',
  },
];

const togglePin = (id: string, current: string[]) => {
  if (!current.includes(id)) return [...current, id];
  return current.length > 1 ? current.filter(item => item !== id) : current;
};

export const useMenuBarCard = (): MenuBarCardState => {
  const [mode, setMode] = useState<MenuBarMode>('selection');
  const [selected, setSelected] = useState('work');
  const [pinned, setPinned] = useState(['work', 'personal']);

  const toggleAccount = useCallback(
    (id: string) => {
      if (mode === 'pinned') setPinned(togglePin.bind(null, id));
      else setSelected(id);
    },
    [mode]
  );

  return { mode, pinned, selected, setMode, toggleAccount };
};
