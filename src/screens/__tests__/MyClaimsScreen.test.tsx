import React from 'react';
import { render } from '../../test-utils';
import { fireEvent, waitFor } from '@testing-library/react-native';
import MyClaimsScreen from '../MyClaimsScreen';

jest.mock('../../lib/supabase');
import { supabase } from '../../lib/supabase';

describe('MyClaimsScreen', () => {
  beforeEach(() => {
    jest.resetAllMocks();

    // auth.getUser
    (supabase.auth.getUser as jest.Mock).mockResolvedValue({
      data: { user: { id: 'u1', email: 'me@example.com', user_metadata: { name: 'Me' } } },
    });

    // realtime channel
    (supabase.channel as jest.Mock).mockReturnValue({
      on: jest.fn().mockReturnThis(),
      subscribe: jest.fn().mockReturnValue({ unsubscribe: jest.fn() }),
    });
    (supabase.removeChannel as jest.Mock).mockImplementation(() => {});

    // queries
    (supabase.from as jest.Mock).mockImplementation((table: string) => {
      if (table === 'claims') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockReturnThis(),
          order: jest.fn().mockResolvedValue({
            data: [{ id: 'c1', item_id: 'i1', purchased: false, created_at: '2025-01-01' }],
            error: null,
          }),
          update: jest.fn().mockReturnValue({
            eq: jest.fn().mockReturnValue({
              eq: jest.fn().mockResolvedValue({ data: null, error: null }),
            }),
          }),
        } as any;
      }
      if (table === 'items') {
        return {
          select: jest.fn().mockReturnThis(),
          in: jest.fn().mockResolvedValue({
            data: [{ id: 'i1', name: 'Lego Set', list_id: 'l1', price: null, url: null }],
            error: null,
          }),
        } as any;
      }
      if (table === 'lists') {
        return {
          select: jest.fn().mockReturnThis(),
          in: jest.fn().mockResolvedValue({
            data: [{ id: 'l1', name: 'Gifts for Bob', event_id: 'e1' }],
            error: null,
          }),
        } as any;
      }
      if (table === 'events') {
        return {
          select: jest.fn().mockReturnThis(),
          in: jest.fn().mockResolvedValue({
            data: [{ id: 'e1', title: 'Birthday Party', event_date: null }],
            error: null,
          }),
        } as any;
      }
      return {} as any;
    });
  });

  it('lists my claims and toggles purchased', async () => {
    const { getByText } = render(<MyClaimsScreen navigation={{}} />);

    // wait for the initial load to settle (silences act warnings)
    await waitFor(() => expect(getByText(/My claimed items/i)).toBeTruthy());
    expect(getByText(/Lego Set/i)).toBeTruthy();
    expect(getByText(/Birthday Party · Gifts for Bob/i)).toBeTruthy();

    fireEvent.press(getByText(/Mark purchased/i));

    // Ensure we attempted to update claims
    expect((supabase.from as jest.Mock)).toHaveBeenCalledWith('claims');
  });
});
