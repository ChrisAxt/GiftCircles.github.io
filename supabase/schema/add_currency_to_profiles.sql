-- Add currency preference to profiles table
-- Default to USD, but users can change it in settings

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS currency VARCHAR(3) DEFAULT 'USD';

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_profiles_currency ON public.profiles(currency);

-- Add comment
COMMENT ON COLUMN public.profiles.currency IS 'ISO 4217 currency code (e.g., USD, EUR, GBP)';
