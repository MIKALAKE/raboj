export type DemoWindow = {
  note: string;
  title: string;
  used: number;
};

export type DemoAccount = {
  color: string;
  cost: string | null;
  from: string;
  id: string;
  label: string;
  limit: number | null;
  limitNote: string;
  provider: string;
  tokens: string;
  week: number[];
  windows: DemoWindow[];
};

export type DemoMetric = 'auto' | 'cost' | 'limits' | 'tokens';

export type MetricOption = {
  id: DemoMetric;
  label: string;
};

export type ProviderSource = 'api' | 'local';

export type Provider = {
  beta: boolean;
  name: string;
  source: ProviderSource;
};

export type Entry = {
  detail: string;
  label: string;
  qty: string;
};

export type FaqItem = {
  answer: string;
  question: string;
};

export type TotalLine = {
  label: string;
  value: string;
};
