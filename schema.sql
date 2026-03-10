-- Create profiles table
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    avatar_url TEXT,
    welcome_message TEXT DEFAULT 'Ready to crush it today?',
    daily_calorie_target INTEGER DEFAULT 2000,
    daily_protein_target INTEGER DEFAULT 150,
    daily_carb_target INTEGER DEFAULT 250,
    daily_fat_target INTEGER DEFAULT 70,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Note: In a real Supabase environment, you would run this in the SQL Editor.
-- I am providing this for reference and to ensure the backend logic matches.

-- Update get_daily_intake logic in main.py to use this table.
