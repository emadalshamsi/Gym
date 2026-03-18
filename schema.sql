-- 1. Profiles Table (Unified Goals & Info)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    avatar_url TEXT,
    welcome_message TEXT DEFAULT 'Ready to crush it today?',
    daily_calorie_target INTEGER DEFAULT 2000,
    daily_protein_target INTEGER DEFAULT 150,
    daily_carb_target INTEGER DEFAULT 250,
    daily_fat_target INTEGER DEFAULT 70,
    daily_water_target_ml INTEGER DEFAULT 2000,
    habit_goals JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Meals Table (The "Parent" entry for a meal)
CREATE TABLE IF NOT EXISTS public.meals (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    meal_type TEXT, -- e.g., 'Breakfast', 'Lunch', 'Dinner', 'Snack'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Meal Items Table (Detailed macros for each food item)
CREATE TABLE IF NOT EXISTS public.meal_items (
    id BIGSERIAL PRIMARY KEY,
    meal_id BIGINT REFERENCES public.meals(id) ON DELETE CASCADE,
    food_name TEXT,
    calories FLOAT DEFAULT 0,
    protein FLOAT DEFAULT 0,
    carbs FLOAT DEFAULT 0,
    fat FLOAT DEFAULT 0,
    weight_grams FLOAT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 4. Water Logs Table (Hydration tracking - Separated from meals)
CREATE TABLE IF NOT EXISTS public.water_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    amount_ml INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Sleep Logs Table
CREATE TABLE public.sleep_logs (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL,
    hours numeric NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);

-- Steps Logs Table
CREATE TABLE public.steps_logs (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL,
    steps integer NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);
