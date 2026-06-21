import { theme as antdTheme, type ThemeConfig } from 'antd';

const fontFamily =
  '-apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Segoe UI", Roboto, Helvetica, Arial, sans-serif';

// Feishu / Lark-inspired light theme. Primary blue #3370FF, neutral greys,
// compact controls and subtle borders.
export const lightTheme: ThemeConfig = {
  token: {
    colorPrimary: '#3370ff',
    colorInfo: '#3370ff',
    colorSuccess: '#2ea121',
    colorError: '#f54a45',
    colorWarning: '#ff8800',
    colorText: '#1f2329',
    colorTextSecondary: '#646a73',
    colorTextTertiary: '#8f959e',
    colorBorder: '#dee0e3',
    colorBorderSecondary: '#eceef1',
    borderRadius: 6,
    controlHeight: 32,
    fontFamily,
  },
  components: {
    Layout: {
      siderBg: '#ffffff',
      bodyBg: '#ffffff',
      headerBg: '#ffffff',
    },
    Menu: {
      itemSelectedBg: '#eaf1ff',
      itemSelectedColor: '#3370ff',
      itemHoverBg: '#f2f3f5',
      itemActiveBg: '#eaf1ff',
      itemHeight: 38,
      itemBorderRadius: 6,
      itemMarginInline: 8,
      iconSize: 16,
    },
    Button: {
      primaryShadow: 'none',
      defaultShadow: 'none',
    },
    Segmented: {
      itemSelectedColor: '#3370ff',
      trackBg: '#f2f3f5',
    },
    Table: {
      headerBg: '#ffffff',
      rowHoverBg: '#f5f6f7',
      borderColor: '#eceef1',
    },
    Modal: {
      borderRadiusLG: 10,
    },
  },
};

// Dark counterpart. AntD's darkAlgorithm derives the full dark palette from the
// seed colours; the explicit neutrals below pin component surfaces to the same
// values index.css uses for its dark tokens, so custom CSS and AntD stay in sync.
export const darkTheme: ThemeConfig = {
  algorithm: antdTheme.darkAlgorithm,
  token: {
    colorPrimary: '#3370ff',
    colorInfo: '#3370ff',
    colorSuccess: '#3fb45b',
    colorError: '#f0837b',
    colorWarning: '#e0a23b',
    colorBgBase: '#16171a',
    colorBgContainer: '#1d1f23',
    colorBgElevated: '#222429',
    colorText: '#e6e8eb',
    colorTextSecondary: '#b4b8bf',
    colorTextTertiary: '#8b9097',
    colorBorder: '#34373d',
    colorBorderSecondary: '#26282d',
    borderRadius: 6,
    controlHeight: 32,
    fontFamily,
  },
  components: {
    Layout: {
      siderBg: '#1d1f23',
      bodyBg: '#16171a',
      headerBg: '#1d1f23',
    },
    Menu: {
      itemSelectedBg: 'rgba(91, 140, 255, 0.16)',
      itemSelectedColor: '#5b8cff',
      itemHoverBg: '#26282d',
      itemActiveBg: 'rgba(91, 140, 255, 0.16)',
      itemHeight: 38,
      itemBorderRadius: 6,
      itemMarginInline: 8,
      iconSize: 16,
    },
    Button: {
      primaryShadow: 'none',
      defaultShadow: 'none',
    },
    Segmented: {
      itemSelectedColor: '#5b8cff',
      itemSelectedBg: '#34373d',
      trackBg: '#26282d',
    },
    Table: {
      headerBg: '#1d1f23',
      rowHoverBg: '#26282d',
      borderColor: '#26282d',
    },
    Modal: {
      borderRadiusLG: 10,
    },
  },
};

// Back-compat alias for existing importers.
export const theme = lightTheme;
