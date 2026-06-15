import type { ThemeConfig } from 'antd';

// Feishu / Lark-inspired light theme. Primary blue #3370FF, neutral greys,
// compact controls and subtle borders.
export const theme: ThemeConfig = {
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
    fontFamily:
      '-apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
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
