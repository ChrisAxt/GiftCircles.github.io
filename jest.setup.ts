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

// Mock react-i18next to return translation keys as values
jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key: string, params?: any) => {
      // Map common translation keys to their English values for tests
      const translations: Record<string, string> = {
        'claimButton.claim': 'Claim',
        'claimButton.unclaim': 'Unclaim',
        'claimButton.claimed': 'Claimed',
        'claimButton.requestSplit': 'Request Split',
        'common.loading': 'Loading...',
        'common.error': 'Error',
        'common.success': 'Success',
        'myClaims.title': 'My claimed items',
        'myClaims.fallbackItem': 'Unknown Item',
        'myClaims.line': 'List item',
        'myClaims.markPurchased': 'Mark as purchased',
        'myClaims.purchased': 'Purchased',
        'eventList.greeting': `Hi ${params?.name || 'there'}!`,
        'eventList.title': 'Your Events',
        'eventDetail.members': 'Members',
        'eventDetail.lists': 'Lists',
      };
      return translations[key] || key;
    },
    i18n: {
      changeLanguage: jest.fn(),
      language: 'en',
    },
  }),
  Trans: ({ children }: any) => children,
  initReactI18next: { type: '3rdParty', init: jest.fn() },
}));

// Mock @react-navigation/native useTheme to provide default theme
jest.mock('@react-navigation/native', () => {
  const actual = jest.requireActual('@react-navigation/native');
  return {
    ...actual,
    useTheme: () => ({
      dark: false,
      colors: {
        primary: '#007AFF',
        background: '#FFFFFF',
        card: '#FFFFFF',
        text: '#000000',
        border: '#CCCCCC',
        notification: '#FF3B30',
      },
    }),
    useFocusEffect: (cb: any) => {
      const React = require('react');
      React.useEffect(() => {
        if (typeof cb === 'function') cb();
      }, []);
    },
    useNavigation: () => ({
      navigate: jest.fn(),
      goBack: jest.fn(),
      setOptions: jest.fn(),
    }),
    useRoute: () => ({
      params: {},
    }),
  };
});

// Mock expo-notifications
jest.mock('expo-notifications', () => ({
  getPermissionsAsync: jest.fn().mockResolvedValue({ status: 'granted' }),
  requestPermissionsAsync: jest.fn().mockResolvedValue({ status: 'granted' }),
  getExpoPushTokenAsync: jest.fn().mockResolvedValue({ data: 'test-token' }),
  setNotificationHandler: jest.fn(),
  addNotificationReceivedListener: jest.fn(() => ({ remove: jest.fn() })),
  addNotificationResponseReceivedListener: jest.fn(() => ({ remove: jest.fn() })),
  AndroidImportance: { MAX: 5 },
}));