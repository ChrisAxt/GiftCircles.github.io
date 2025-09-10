import 'react-native-url-polyfill/auto';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import Constants from 'expo-constants';

const fromEnv = {
  url: process.env.EXPO_PUBLIC_SUPABASE_URL,
  key: process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY,
};
const fromExtra = {
  url: (Constants.expoConfig?.extra as any)?.supabaseUrl,
  key: (Constants.expoConfig?.extra as any)?.supabaseAnonKey,
};

const supabaseUrl = (fromEnv.url || fromExtra.url) as string;
const supabaseAnonKey = (fromEnv.key || fromExtra.key) as string;

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn('Missing Supabase credentials: set EXPO_PUBLIC_SUPABASE_URL/ANON_KEY or expo.extra in app.json');
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: AsyncStorage as any,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
  realtime: { params: { eventsPerSecond: 5 } },
});
