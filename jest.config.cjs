// jest.config.cjs
module.exports = {
  preset: 'jest-expo', // <<< important for Expo modules
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
