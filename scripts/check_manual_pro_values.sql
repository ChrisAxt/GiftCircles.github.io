-- Check manual_pro values for your users
SELECT
    display_name,
    plan,
    pro_until,
    manual_pro,
    public.is_pro(id) as is_pro_result
FROM public.profiles
WHERE display_name IN ('Chris Axt', 'Sarah Axt', 'Jane');

-- Show the current is_pro function definition
SELECT pg_get_functiondef('public.is_pro'::regproc);
