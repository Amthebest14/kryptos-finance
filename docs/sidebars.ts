import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  docsSidebar: [
    'index',
    'getting-started',
    'architecture',
    'privacy-model',
    {
      type: 'category',
      label: 'Using the App',
      items: [
        'using-the-app/core-loop',
        'using-the-app/staying-alive',
        'using-the-app/liquidation',
        'using-the-app/staking',
      ],
    },
    {
      type: 'category',
      label: 'Privacy',
      items: [
        'privacy/threat-model',
        'privacy/trusted-setup',
        'privacy/known-limitations',
      ],
    },
    {
      type: 'category',
      label: 'Reference',
      items: [
        'reference/deployed-contracts',
      ],
    },
  ],
};

export default sidebars;
