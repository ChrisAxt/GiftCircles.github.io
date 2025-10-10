# Currency Support Feature

## Overview

The app now supports multiple currencies with both auto-detection and manual selection capabilities.

## Implementation Status

### ✅ Completed
1. **Database**: Added `currency` column to `profiles` table
2. **Utility**: Created `src/lib/currency.ts` with formatting functions
3. **UI**: Added currency selector to PreferencesCard in settings
4. **Auto-detection**: Detects user's currency based on locale on first login

### 🔄 Remaining Tasks

#### 1. Update Price Displays

Replace hardcoded `$` symbols with the `formatPrice()` function:

**Files to update:**
- `src/components/ItemRow.tsx` (line 8)
- `src/screens/ListDetailScreen.tsx` (line 429)
- Any other files displaying prices

**How to do it:**

```typescript
// Before:
<Text>${item.price.toFixed(2)}</Text>

// After:
import { formatPrice } from '../lib/currency';
import { useUserCurrency } from '../hooks/useUserCurrency'; // Need to create this hook

const currencyCode = useUserCurrency();
<Text>{formatPrice(item.price, currencyCode)}</Text>
```

#### 2. Create `useUserCurrency` Hook

Create `src/hooks/useUserCurrency.ts`:

```typescript
import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';

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
```

#### 3. Add Translation Keys

Add to `src/i18n/locales/en.ts`:

```typescript
profile: {
  settings: {
    // ... existing settings
    currency: 'Currency',
    currencyUpdated: 'Currency preference updated',
  },
  alerts: {
    // ... existing alerts
    updateFailed: 'Update failed',
  },
}
```

#### 4. Apply Database Migration

Run in Supabase SQL Editor:
```sql
-- From file: supabase/schema/add_currency_to_profiles.sql
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS currency VARCHAR(3) DEFAULT 'USD';

CREATE INDEX IF NOT EXISTS idx_profiles_currency ON public.profiles(currency);

COMMENT ON COLUMN public.profiles.currency IS 'ISO 4217 currency code (e.g., USD, EUR, GBP)';
```

## Supported Currencies

The system supports 29 major world currencies:

- USD ($) - US Dollar
- EUR (€) - Euro
- GBP (£) - British Pound
- CAD (CA$) - Canadian Dollar
- AUD (A$) - Australian Dollar
- JPY (¥) - Japanese Yen
- CNY (¥) - Chinese Yuan
- INR (₹) - Indian Rupee
- CHF - Swiss Franc
- SEK (kr) - Swedish Krona
- NOK (kr) - Norwegian Krone
- DKK (kr) - Danish Krone
- And 17 more...

See `src/lib/currency.ts` for the complete list.

## Features

### Auto-Detection
- On first login, currency is automatically detected from user's system locale
- Falls back to USD if detection fails
- Automatically saved to user profile

### Manual Selection
- Users can change currency anytime in Settings
- Modal picker with searchable list of all currencies
- Shows currency symbol, name, and code
- Updates immediately across the app

### Formatting
- Proper decimal places (e.g., JPY has no decimals)
- Correct symbol placement (e.g., "10 kr" vs "$10")
- Consistent formatting throughout the app

## Usage Example

```typescript
import { formatPrice } from '../lib/currency';
import { useUserCurrency } from '../hooks/useUserCurrency';

function MyComponent() {
  const currency = useUserCurrency();
  const price = 99.99;

  return (
    <Text>{formatPrice(price, currency)}</Text>
    // Output varies by currency:
    // USD: $99.99
    // EUR: €99.99
    // JPY: ¥100
    // SEK: 99.99 kr
  );
}
```

## Testing

1. **Auto-detection**: Sign up with different locale settings
2. **Manual change**: Go to Settings > Currency and select different options
3. **Price display**: Add items with prices and verify correct formatting
4. **Persistence**: Close app and reopen, currency should be remembered

## Notes

- Currency preference is per-user, not per-event
- All prices are stored as numbers in database (no currency info)
- Formatting happens on display only
- Future: Could add currency conversion features
