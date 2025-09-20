// src/test-utils.tsx
import React, { PropsWithChildren } from 'react';
import { render as rtlRender } from '@testing-library/react-native';
import { NavigationContainer } from '@react-navigation/native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

export function render(ui: React.ReactElement, options?: Parameters<typeof rtlRender>[1]) {
  const Wrapper = ({ children }: PropsWithChildren) => (
    <SafeAreaProvider>
      <NavigationContainer>{children}</NavigationContainer>
    </SafeAreaProvider>
  );
  return rtlRender(ui, { wrapper: Wrapper, ...options });
}
