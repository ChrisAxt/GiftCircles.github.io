// App.tsx
import './src/i18n';
import React from 'react';
import { StatusBar } from 'expo-status-bar';
import RootNavigator from './src/navigation';
import 'react-native-gesture-handler';
import Toast from 'react-native-toast-message';
import { SafeAreaProvider } from 'react-native-safe-area-context';


export default function App() {
  return (
    <SafeAreaProvider>
      <RootNavigator />
      <StatusBar style="auto" />
    </SafeAreaProvider>
  );
}
