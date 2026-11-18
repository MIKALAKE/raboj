export type MenuBarMode = 'icon' | 'pinned' | 'selection';

export type ModeOption = {
  id: MenuBarMode;
  label: string;
  note: string;
};

export type MenuBarCardState = {
  mode: MenuBarMode;
  pinned: string[];
  selected: string;
  setMode: (mode: MenuBarMode) => void;
  toggleAccount: (id: string) => void;
};
