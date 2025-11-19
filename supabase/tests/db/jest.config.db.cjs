// Jest configuration for database integration tests
// No React Native mocks needed - these are pure database tests

module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testTimeout: 60000, // 60 seconds for database operations
  setupFilesAfterEnv: ['<rootDir>/jest.setup.db.ts'],
  transform: {
    '^.+\\.tsx?$': ['ts-jest', {
      tsconfig: {
        target: 'ES2020',
        module: 'commonjs',
        esModuleInterop: true,
        allowSyntheticDefaultImports: true,
        strict: false,
      },
    }],
  },
  testMatch: ['**/*.test.ts'],
  moduleFileExtensions: ['ts', 'js', 'json'],
  verbose: true,
  // Run tests sequentially to avoid database conflicts
  maxWorkers: 1,
};
