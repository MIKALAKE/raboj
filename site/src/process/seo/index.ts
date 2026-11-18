import type { FaqItem } from 'Constants/types';
import { APP_VERSION, AUTHOR, GITHUB_URL, RELEASES_URL, SITE_NAME } from 'Constants';

import type { StructuredDataInput } from './types';

const toQuestion = (item: FaqItem) => ({
  '@type': 'Question',
  acceptedAnswer: { '@type': 'Answer', text: item.answer },
  name: item.question,
});

export const structuredData = ({
  description,
  faq,
  imageUrl,
  pageUrl,
}: StructuredDataInput) => [
  {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    applicationCategory: 'DeveloperApplication',
    applicationSubCategory: 'AI usage monitor',
    author: { '@type': 'Person', name: AUTHOR },
    description,
    downloadUrl: RELEASES_URL,
    image: imageUrl,
    installUrl: RELEASES_URL,
    isAccessibleForFree: true,
    license: `${GITHUB_URL}/blob/main/LICENSE`,
    name: SITE_NAME,
    offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
    operatingSystem: 'macOS 14 or later',
    sameAs: [GITHUB_URL],
    softwareVersion: APP_VERSION,
    url: pageUrl,
  },
  {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: faq.map(toQuestion),
  },
];
