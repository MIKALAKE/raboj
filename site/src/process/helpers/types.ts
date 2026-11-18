import type { DemoAccount, DemoMetric } from 'Constants/types';

export type MetricValue = {
  fraction: number | null;
  note: string;
  text: string;
};

export type MetricResolver = (account: DemoAccount) => MetricValue;

export type PaceInput = {
  elapsedFraction: number;
  now: Date;
  usedPercent: number;
  windowHours: number;
};

export type PaceResult = {
  projectedPercent: number;
  text: string;
  warn: boolean;
};

export type { DemoAccount, DemoMetric };
