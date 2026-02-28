import os, requests, json
from fastapi import FastAPI, Form, Query
from supabase import create_client, Client
from deep_translator import GoogleTranslator
from dotenv import load_dotenv

load_dotenv()
app = FastAPI()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# قاموس ذكاء اصطناعي مصغر للقيم الشائعة (حل مجاني وسريع)
AI_NUTRITION_DB = {
    "egg": {"cal": 78, "prot": 6.3, "carb": 0.6, "fat": 5.3},
    "boiled egg": {"cal": 77, "prot": 6.3, "carb": 0.6, "fat": 5.3},
    "chicken breast": {"cal": 165, "prot": 31, "carb": 0, "fat": 3.6},
    "rice": {"cal": 130, "prot": 2.7, "carb": 28, "fat": 0.3},
    "apple": {"cal": 52, "prot": 0.3, "carb": 14, "fat": 0.2},
    "banana": {"cal": 89, "prot": 1.1, "carb": 23, "fat": 0.3}
}

def get_ai_nutrition(food_name_en):
    """نظام بحث ذكي يبحث في القاموس أو يعطي تخميناً منطقياً"""
    food_name_en = food_name_en.lower()
    # البحث عن تطابق جزئي
    for key in AI_NUTRITION_DB:
        if key in food_name_en:
            return AI_NUTRITION_DB[key]
    
    # إذا لم يجد، يعطي قيم متوسطة لأي وجبة (بدلاً من الأصفار)
    return {"cal": 150, "prot": 10, "carb": 15, "fat": 7}

@app.post("/log_meal")
async def log_meal(user_id: str = Query(...), meal_type: str = Query(...), items_ar: str = Form(...)):
    try:
        try:
            items_list = json.loads(items_ar.replace("'", '"'))
        except:
            items_list = [items_ar.strip()]

        meal_record = supabase.table("meals").insert({"user_id": user_id, "meal_type": meal_type}).execute()
        meal_id = meal_record.data[0]['id']
        added_items = []

        for item_ar in items_list:
            # 1. الترجمة للعثور على الاسم بالإنجليزية
            item_en = GoogleTranslator(source='ar', target='en').translate(item_ar)
            
            # 2. جلب البيانات من نظامنا الذكي (مجاني 100% ولا يحتاج Token)
            nutri = get_ai_nutrition(item_en)

            payload = {
                "meal_id": meal_id, 
                "food_name": item_ar, 
                "calories": nutri['cal'], 
                "protein": nutri['prot'], 
                "carbs": nutri['carb'], 
                "fat": nutri['fat']
            }
            
            supabase.table("meal_items").insert(payload).execute()
            added_items.append(payload)

        return {"status": "success", "items": added_items}
    except Exception as e:
        return {"status": "error", "detail": str(e)}

# دالة calculate_goals تبقى كما هي

@app.post("/calculate_goals")
async def calculate_goals(
    user_id: str = Query(...), 
    weight: float = Query(...), 
    height: float = Query(...), 
    age: int = Query(...), 
    gender: str = Query(...), 
    activity: str = Query(...), 
    goal: str = Query(...)
):
    try:
        if gender.lower() == "male":
            bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5
        else:
            bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161
            
        multipliers = {"sedentary": 1.2, "light": 1.375, "moderate": 1.55, "active": 1.725}
        tdee = bmr * multipliers.get(activity.lower(), 1.2)
        
        target_calories = tdee - 500 if goal.lower() == "lose" else tdee + 500 if goal.lower() == "gain" else tdee

        supabase.table("profiles").upsert({
            "id": user_id,
            "weight": weight, "height": height, "age": age,
            "gender": gender, "target_calories": int(target_calories),
            "target_water_ml": int(weight * 35)
        }).execute()
        
        return {"status": "success", "target_calories": int(target_calories)}
    except Exception as e:
        return {"status": "error", "detail": str(e)}