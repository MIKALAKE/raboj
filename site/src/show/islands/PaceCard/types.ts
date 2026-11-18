export type WindowOption = {
  hours: number;
  id: string;
  label: string;
};

export type PaceCardState = {
  elapsed: number;
  onElapsed: (value: number) => void;
  onUsed: (value: number) => void;
  onWindow: (id: string) => void;
  projected: number;
  text: string;
  used: number;
  warn: boolean;
  windowId: string;
};
