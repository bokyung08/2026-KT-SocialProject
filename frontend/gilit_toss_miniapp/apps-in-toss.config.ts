import { defineConfig } from '@apps-in-toss/web-framework/config';

export default defineConfig({
  appName: 'pmsafeline',
  brand: {
    primaryColor: '#E8453C', // 길잇 브랜드 컬러 (AppColors.brand)
  },
  permissions: [],
  webBundleDir: 'dist',
});
