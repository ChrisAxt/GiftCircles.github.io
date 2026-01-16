-- Check if manual_pro column exists and what values users have

-- Check your profile columns related to Pro
SELECT
    display_name,
    plan,
    pro_until,
    -- Try to select manual_pro if it exists
    CASE
        WHEN EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public'
            AND table_name = 'profiles'
            AND column_name = 'manual_pro'
        ) THEN 'Column exists'
        ELSE 'Column does not exist'
    END as manual_pro_status
FROM public.profiles
WHERE display_name IN ('Chris Axt', 'Sarah Axt', 'Jane')
LIMIT 1;

-- If manual_pro exists, show the values
-- Uncomment this if the above shows 'Column exists':
-- SELECT
--     display_name,
--     plan,
--     manual_pro,
--     public.is_pro(id) as is_pro_result
-- FROM public.profiles
-- WHERE display_name IN ('Chris Axt', 'Sarah Axt', 'Jane');
