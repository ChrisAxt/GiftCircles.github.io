// App.tsx
import './src/i18n';
import React from 'react';
import { StatusBar } from 'expo-status-bar';
import RootNavigator from './src/navigation';
import 'react-native-gesture-handler';
import Toast, { BaseToast, ErrorToast } from 'react-native-toast-message';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { useColorScheme } from 'react-native';


export default function App() {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';

  const toastConfig = {
    success: (props: any) => (
      <BaseToast
        {...props}
        style={{
          borderLeftColor: '#10b981',
          backgroundColor: isDark ? '#1f2937' : '#ffffff',
        }}
        contentContainerStyle={{ paddingHorizontal: 15 }}
        text1Style={{
          fontSize: 16,
          fontWeight: '600',
          color: isDark ? '#ffffff' : '#000000',
        }}
        text2Style={{
          fontSize: 14,
          color: isDark ? '#d1d5db' : '#6b7280',
        }}
      />
    ),
    error: (props: any) => (
      <ErrorToast
        {...props}
        style={{
          borderLeftColor: '#ef4444',
          backgroundColor: isDark ? '#1f2937' : '#ffffff',
        }}
        contentContainerStyle={{ paddingHorizontal: 15 }}
        text1Style={{
          fontSize: 16,
          fontWeight: '600',
          color: isDark ? '#ffffff' : '#000000',
        }}
        text2Style={{
          fontSize: 14,
          color: isDark ? '#d1d5db' : '#6b7280',
        }}
      />
    ),
    info: (props: any) => (
      <BaseToast
        {...props}
        style={{
          borderLeftColor: '#3b82f6',
          backgroundColor: isDark ? '#1f2937' : '#ffffff',
        }}
        contentContainerStyle={{ paddingHorizontal: 15 }}
        text1Style={{
          fontSize: 16,
          fontWeight: '600',
          color: isDark ? '#ffffff' : '#000000',
        }}
        text2Style={{
          fontSize: 14,
          color: isDark ? '#d1d5db' : '#6b7280',
        }}
      />
    ),
  };

  return (
    <SafeAreaProvider>
      <StatusBar style={isDark ? 'light' : 'dark'} />
      <RootNavigator />
      <Toast config={toastConfig} />
    </SafeAreaProvider>
  );
}
