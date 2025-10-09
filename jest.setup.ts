// jest.setup.ts

// Load test environment variables
require('dotenv').config({ path: '.env.test' });

// Mock Reanimated v2
jest.mock('react-native-reanimated', () => require('react-native-reanimated/mock'));

// RN Animated helper: path may not exist on your RN version → virtual mock
try {
  require.resolve('react-native/Libraries/Animated/NativeAnimatedHelper');
  // @ts-ignore
  jest.mock('react-native/Libraries/Animated/NativeAnimatedHelper');
} catch {
  jest.mock(
    'react-native/Libraries/Animated/NativeAnimatedHelper',
    () => ({}),
    { virtual: true }
  );
}

// Mock expo-linear-gradient as a simple passthrough View
jest.mock('expo-linear-gradient', () => {
  const React = require('react');
  const { View } = require('react-native');
  const LinearGradient = ({ children }: any) => React.createElement(View, null, children);
  return { LinearGradient };
});

// Mock react-native-toast-message (ESM) so Jest doesn’t have to transform it
jest.mock('react-native-toast-message', () => ({
  __esModule: true,
  default: {
    show: jest.fn(),
    hide: jest.fn(),
  },
}));

// (Optional) gesture-handler setup; ignore if not installed
try {
  require('react-native-gesture-handler/jestSetup');
} catch {}

// Mock react-native-safe-area-context so hooks don't crash in tests
jest.mock('react-native-safe-area-context', () => {
  const inset = { top: 0, right: 0, bottom: 0, left: 0 };
  return {
    // keep type exports if needed
    ...jest.requireActual('react-native-safe-area-context'),
    SafeAreaProvider: ({ children }: any) => children,
    SafeAreaView: ({ children }: any) => children,
    useSafeAreaInsets: () => inset,
  };
});