import type {
  DemoAccount,
  DemoMetric,
  MetricResolver,
  MetricValue,
  PaceInput,
  PaceResult,
} from './types';

const limitsValue = (account: DemoAccount): MetricValue =>
  account.limit === null
    ? { fraction: null, note: `${account.provider} has no plan limits`, text: '—' }
    : {
        fraction: account.limit / 100,
        note: account.limitNote,
        text: `${account.limit}%`,
      };

const costValue = (account: DemoAccount): MetricValue =>
  account.cost
    ? { fraction: null, note: 'billed today', text: account.cost }
    : { fraction: null, note: `${account.provider} doesn’t report cost`, text: '—' };

const tokensValue = (account: DemoAccount): MetricValue => ({
  fraction: null,
  note: 'tokens today',
  text: account.tokens,
});

const autoValue = (account: DemoAccount): MetricValue =>
  account.limit === null ? costValue(account) : limitsValue(account);

const METRIC_RESOLVERS: Record<DemoMetric, MetricResolver> = {
  auto: autoValue,
  cost: costValue,
  limits: limitsValue,
  tokens: tokensValue,
};

export const metricValue = (metric: DemoMetric, account: DemoAccount) =>
  METRIC_RESOLVERS[metric](account);

export const formatClock = (date: Date) =>
  date.toLocaleTimeString([], { hour: '2-digit', hour12: false, minute: '2-digit' });

export const formatSpan = (hours: number) => {
  if (hours >= 24) return `${Math.floor(hours / 24)}d ${Math.round(hours % 24)}h`;
  const minutes = String(Math.round((hours % 1) * 60)).padStart(2, '0');
  return `${Math.floor(hours)}h ${minutes}m`;
};

export const projectPace = ({
  elapsedFraction,
  now,
  usedPercent,
  windowHours,
}: PaceInput): PaceResult => {
  if (usedPercent >= 100)
    return { projectedPercent: 100, text: 'Limit reached', warn: true };
  if (usedPercent === 0) {
    return { projectedPercent: 0, text: 'On track · about 0% by reset', warn: false };
  }
  if (elapsedFraction < 0.05) {
    return { projectedPercent: usedPercent, text: 'Too early to tell', warn: false };
  }
  const elapsed = elapsedFraction * windowHours;
  const rate = usedPercent / elapsed;
  const projected = usedPercent + rate * (windowHours - elapsed);
  if (projected < 100) {
    return {
      projectedPercent: projected,
      text: `On track · about ${Math.round(projected)}% by reset`,
      warn: false,
    };
  }
  const hoursToLimit = (100 - usedPercent) / rate;
  const at = new Date(now.getTime() + hoursToLimit * 3_600_000);
  return {
    projectedPercent: 100,
    text: `Limit around ${formatClock(at)}, in ${formatSpan(hoursToLimit)}`,
    warn: true,
  };
};
