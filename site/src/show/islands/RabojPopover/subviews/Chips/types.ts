import type { Selection } from '../../types';

export type ChipsProps = {
  hint: boolean;
  onSelect: (selection: Selection) => void;
  selection: Selection;
};

export type ChipOption = {
  color: string;
  id: Selection;
  label: string;
};
