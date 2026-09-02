import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'Kryptos Finance',
  tagline: 'A private borrow-lend protocol on Horizen',
  favicon: 'img/favicon.png',

  future: {
    v4: true,
  },

  url: 'https://docs.kryptos.finance',
  baseUrl: '/',

  organizationName: 'Amthebest14',
  projectName: 'kryptos-finance',

  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/Amthebest14/kryptos-finance/tree/main/docs/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    image: 'img/logo.png',
    colorMode: {
      defaultMode: 'dark',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'Kryptos Finance',
      logo: {
        alt: 'Kryptos Finance',
        src: 'img/logo.png',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'docsSidebar',
          position: 'left',
          label: 'Docs',
        },
        {
          href: 'https://testnet.kryptos.finance',
          label: 'Launch App',
          position: 'right',
          className: 'navbar-launch-app',
        },
        {
          href: 'https://github.com/Amthebest14/kryptos-finance',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {label: 'Introduction', to: '/'},
            {label: 'Getting Started', to: '/getting-started'},
            {label: 'Architecture', to: '/architecture'},
            {label: 'Privacy Threat Model', to: '/privacy/threat-model'},
          ],
        },
        {
          title: 'Protocol',
          items: [
            {label: 'Launch App', href: 'https://testnet.kryptos.finance'},
            {label: 'Deployed Contracts', to: '/reference/deployed-contracts'},
            {label: 'Known Limitations', to: '/privacy/known-limitations'},
          ],
        },
        {
          title: 'More',
          items: [
            {label: 'GitHub', href: 'https://github.com/Amthebest14/kryptos-finance'},
          ],
        },
      ],
      copyright: `© ${new Date().getFullYear()} Kryptos Finance. Built on Horizen Testnet.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['solidity', 'bash', 'json'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
