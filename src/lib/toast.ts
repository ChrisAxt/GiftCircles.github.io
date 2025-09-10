// src/lib/toast.ts
import Toast from 'react-native-toast-message';

type Opts = { text2?: string; visibilityTime?: number };

export const toast = {
  success(text1: string, opts: Opts = {}) {
    Toast.show({ type: 'success', position: 'bottom', text1, ...opts });
  },
  error(text1: string, opts: Opts = {}) {
    Toast.show({ type: 'error', position: 'bottom', text1, ...opts });
  },
  info(text1: string, opts: Opts = {}) {
    Toast.show({ type: 'info', position: 'bottom', text1, ...opts });
  },
};
