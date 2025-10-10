import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';

/**
 * Hook to get the current user's currency preference
 * Returns the ISO 4217 currency code (e.g., 'USD', 'EUR', 'GBP')
 * Defaults to 'USD' if not set or if there's an error
 */
export const useUserCurrency = (): string => {
  const [currency, setCurrency] = useState<string>('USD');

  useEffect(() => {
    let cancelled = false;

    (async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user || cancelled) return;

        const { data } = await supabase
          .from('profiles')
          .select('currency')
          .eq('id', user.id)
          .maybeSingle();

        if (data?.currency && !cancelled) {
          setCurrency(data.currency);
        }
      } catch (e) {
        console.error('Failed to load currency:', e);
      }
    })();

    return () => { cancelled = true; };
  }, []);

  return currency;
};
