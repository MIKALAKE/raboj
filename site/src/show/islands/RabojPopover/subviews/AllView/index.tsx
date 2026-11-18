import { metricValue } from 'Helpers';
import { DEMO_ACCOUNTS, METRIC_OPTIONS } from 'Constants';
import type { DemoAccount, DemoMetric, MetricOption } from 'Constants/types';

import UsageRow from '../UsageRow';
import type { AllViewProps } from './types';

const renderTab = ({ metric, onMetric }: AllViewProps, option: MetricOption) => (
  <button
    aria-pressed={option.id === metric}
    className={`h-[22px] flex-1 rounded-[6px] border-0 text-[11px] font-medium ${option.id === metric ? 'bg-mac-fg text-mac-bg' : 'bg-transparent'}`}
    key={option.id}
    onClick={onMetric.bind(null, option.id)}
    type='button'>
    {option.label}
  </button>
);

const renderRow = (metric: DemoMetric, account: DemoAccount) => {
  const value = metricValue(metric, account);
  return (
    <UsageRow
      color={account.color}
      dot={account.color}
      fraction={value.fraction}
      key={account.id}
      note={value.note}
      subtitle={account.provider}
      title={account.label}
      value={value.text}
    />
  );
};

const AllView = (props: AllViewProps) => (
  <>
    <div className='my-2.5 flex justify-between text-[11.5px]'>
      <b className='font-semibold'>All accounts · today</b>
      <span className='text-mac-muted'>{DEMO_ACCOUNTS.length} accounts</span>
    </div>
    <div className='mb-2 flex gap-0.5 rounded-[8px] bg-black/6 p-0.5'>
      {METRIC_OPTIONS.map(renderTab.bind(null, props))}
    </div>
    <div className='grid gap-[7px]'>
      {DEMO_ACCOUNTS.map(renderRow.bind(null, props.metric))}
    </div>
  </>
);

export default AllView;
