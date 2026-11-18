import type { DemoMetric } from 'Constants/types';

export type AllViewProps = {
  metric: DemoMetric;
  onMetric: (metric: DemoMetric) => void;
};
