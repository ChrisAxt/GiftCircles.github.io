import React from 'react';
import { render, waitFor } from '@testing-library/react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import EventListScreen from '../EventListScreen';
import { supabase } from '../../lib/supabase';

const realError = console.error;
beforeAll(() => {
  console.error = (...args: any[]) => {
    if (String(args[0]).includes('eq is not a function')) return;
    realError(...args);
  };
});
afterAll(() => { console.error = realError; });

jest.mock('@react-navigation/native', () => {
  const actual = jest.requireActual('@react-navigation/native');
  return {
    ...actual,
    useFocusEffect: (cb: any) => {
      const React = require('react');
      const { useEffect } = React;
      useEffect(() => {
        if (typeof cb === 'function') cb();
      }, []);
    },
  };
});

jest.mock('expo-linear-gradient', () => {
  const React = require('react');
  const { View } = require('react-native');
  return { LinearGradient: ({ children }: any) => <View>{children}</View> };
});

jest.mock('../../lib/claimCounts', () => ({
  fetchClaimCountsByList: jest.fn().mockResolvedValue({ l1: 1 }),
}));

// src/screens/__tests__/EventListScreen.test.tsx (top of file)
jest.mock('../../lib/supabase', () => {
  const sampleUser = {
    id: 'user-1',
    email: 'me@example.com',
    user_metadata: { name: 'Me' },
  };

  // Small helpers to produce the shape EventListScreen expects.
  const makeSelectChain = (table: string) => {
    const chain: any = {
      // events: .order(...) is used
      order: jest.fn().mockResolvedValue({
        data: table === 'events'
          ? [{ id: 'ev1', title: 'Party', created_at: '2025-01-01' }]
          : [],
        error: null,
      }),

      // events, profiles, etc: .eq(...).maybeSingle() is used
      eq: jest.fn().mockReturnValue({
        maybeSingle: jest.fn().mockResolvedValue({
          data:
            table === 'profiles'
              ? { display_name: 'Me' }
              : table === 'events'
                ? { id: 'ev1', title: 'Party', created_at: '2025-01-01' }
                : null,
          error: null,
        }),
      }),

      // lists, items, claims, event_members: .in(...) is used
      in: jest.fn().mockResolvedValue({
        data:
          table === 'lists'
            ? [{ id: 'list-1', event_id: 'ev1' }]
            : table === 'items'
              ? [{ id: 'item-1', list_id: 'list-1' }]
              : table === 'claims'
                ? [] // no claims needed for this test
                : table === 'event_members'
                  ? [{ event_id: 'ev1', user_id: sampleUser.id }]
                  : [],
        error: null,
      }),

      // fallback if .maybeSingle() is called directly
      maybeSingle: jest.fn().mockResolvedValue({ data: null, error: null }),
    };

    return chain;
  };

  return {
    supabase: {
      auth: {
        getSession: jest.fn().mockResolvedValue({ data: { session: {} }, error: null }),
        getUser: jest.fn().mockResolvedValue({ data: { user: sampleUser }, error: null }),
      },
      from: jest.fn((table: string) => ({
        select: jest.fn(() => makeSelectChain(table)),
      })),
      rpc: jest.fn(),
      channel: jest.fn(() => ({
        on: jest.fn().mockReturnThis(),
        subscribe: jest.fn(),
      })),
      removeChannel: jest.fn(),
    },
  };
});

describe('EventListScreen', () => {
  it('shows events and claim counts tile', async () => {
    const { getByText } = render(
      <SafeAreaProvider>
        <EventListScreen navigation={{ navigate: jest.fn() }} />
      </SafeAreaProvider>
    );

    await waitFor(() => {
      // Greeting
      expect(getByText(/Welcome back/i)).toBeTruthy();
      // Event title
      expect(getByText('Party')).toBeTruthy();
      // Stats tiles
      expect(getByText('Active Events')).toBeTruthy();
      expect(getByText('Items Claimed')).toBeTruthy();
      // Claimed count from mocked fetchClaimCountsByList
      expect(getByText('1')).toBeTruthy();
    });
  });
});
