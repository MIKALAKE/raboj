import type { DemoMetric } from 'Constants/types';

export type Selection = 'all' | string;

export type RabojPopoverProps = {
  hint?: boolean;
};

export type PopoverState = {
  dismissHint: () => void;
  metric: DemoMetric;
  select: (selection: Selection) => void;
  selection: Selection;
  setMetric: (metric: DemoMetric) => void;
  showHint: boolean;
};
