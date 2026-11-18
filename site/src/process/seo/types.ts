import type { FaqItem } from 'Constants/types';

export type StructuredDataInput = {
  description: string;
  faq: FaqItem[];
  imageUrl: string;
  pageUrl: string;
};
