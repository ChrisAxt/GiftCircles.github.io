// src/components/__tests__/ClaimButton.test.tsx
import React from 'react';
import { render, fireEvent, waitFor } from '@testing-library/react-native';
import ClaimButton from '../ClaimButton';
import { supabase } from '../../lib/supabase';

jest.mock('../../lib/supabase', () => ({
  supabase: {
    rpc: jest.fn(),
  },
}));

jest.mock('../../lib/toast', () => ({
  toast: { success: jest.fn(), error: jest.fn(), info: jest.fn() },
}));

describe('ClaimButton', () => {
  beforeEach(() => {
    (supabase.rpc as jest.Mock).mockReset();
  });

  it('claims an unclaimed item', async () => {
    (supabase.rpc as jest.Mock).mockResolvedValueOnce({ data: { ok: true }, error: null });

    const onChanged = jest.fn();
    const { getByLabelText } = render(
      <ClaimButton itemId="it1" claims={[]} meId="me" onChanged={onChanged} />
    );

    fireEvent.press(getByLabelText('Claim'));

    await waitFor(() => {
      expect(supabase.rpc).toHaveBeenCalled();
      expect(onChanged).toHaveBeenCalled();
    });
  });

  it('unclaims my claim', async () => {
    (supabase.rpc as jest.Mock).mockResolvedValueOnce({ data: { ok: true }, error: null });

    const onChanged = jest.fn();
    const myClaim = { id: 'c1', item_id: 'it1', claimer_id: 'me' };
    const { getByLabelText } = render(
      <ClaimButton itemId="it1" claims={[myClaim]} meId="me" onChanged={onChanged} />
    );

    fireEvent.press(getByLabelText('Unclaim'));

    await waitFor(() => {
      expect(supabase.rpc).toHaveBeenCalled();
      expect(onChanged).toHaveBeenCalled();
    });
  });
});
