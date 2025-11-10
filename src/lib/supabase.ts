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

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: AsyncStorage as any,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
  realtime: {
    params: {
      eventsPerSecond: 5
    }
  },
  global: {
    headers: {
      'X-Client-Info': 'giftcircles-mobile',
    },
    // Connection pooling and timeout configuration
    // Note: Supabase handles connection pooling via PgBouncer automatically
    // These settings control client-side behavior
    fetch: (url: RequestInfo | URL, options: RequestInit = {}) => {
      // Add timeout to all requests (30 seconds for queries, 60 for RPCs)
      const urlString = typeof url === 'string' ? url : url.toString();
      const isRPC = urlString.includes('/rpc/');
      const timeout = isRPC ? 60000 : 30000;

      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), timeout);

      return fetch(url, {
        ...options,
        signal: controller.signal,
      })
        .finally(() => clearTimeout(timeoutId))
        .catch((error) => {
          if (error.name === 'AbortError') {
            throw new Error(`Request timeout after ${timeout}ms`);
          }
          throw error;
        });
    },
  },
  db: {
    schema: 'public',
  },
});
