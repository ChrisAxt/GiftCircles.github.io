// jest.config.cjs
module.exports = {
  preset: 'jest-expo', // <<< important for Expo modules
  testTimeout: 30000, // 30 seconds for database operations
  setupFilesAfterEnv: [
    '<rootDir>/jest.setup.ts',
    '@testing-library/jest-native/extend-expect',
  ],
  transformIgnorePatterns: [
    // Allow these node_modules to be transformed
    'node_modules/(?!(react-native' +
      '|@react-native' +
      '|react-native-.*' +
      '|@react-navigation/.*' +
      '|expo(nent)?' +
      '|@expo(nent)?/.*' +
      '|expo-.*' +
      '|@expo/.*' +
      '|@unimodules/.*' +
      '|unimodules-.*' +
      '|sentry-expo' +
      '|native-base' +
      '|react-native-svg' +
      '|react-native-toast-message' + // <<< allow this ESM package
    ')/)',
  ],
  testPathIgnorePatterns: ['/node_modules/', '/android/', '/ios/'],
  moduleFileExtensions: ['ts', 'tsx', 'js', 'jsx', 'json', 'node'],
};
