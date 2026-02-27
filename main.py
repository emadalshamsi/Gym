import os
import requests
from fastapi import FastAPI
from supabase import create_client, Client
from deep_translator import GoogleTranslator
from dotenv import load_dotenv

# تحميل المتغيرات من ملف .env
load_dotenv()

app = FastAPI()

# إعداد الربط مع Supabase و API Ninjas
url: str = os.getenv("SUPABASE_URL")
key: str = os.getenv("SUPABASE_ANON_KEY")
ninjas_key: str = os.getenv("NINJAS_API_KEY")

supabase: Client = create_client(url, key)

# --- قسم التغذية (API Ninjas) ---

def fetch_nutrition(food_name_en):
    api_url = f'https://api.api-ninjas.com/v1/nutrition?query={food_name_en}'
    response = requests.get(api_url, headers={'X-Api-Key': ninjas_key})
    return response.json()

@app.post("/log_meal")
async def log_meal(user_id: str, meal_type: str, items_ar: list):
    """تسجيل وجبة تحتوي على عدة أصناف بالعربي"""
    # إنشاء سجل الوجبة
    meal_record = supabase.table("meals").insert({"user_id": user_id, "meal_type": meal_type}).execute()
    meal_id = meal_record.data[0]['id']
    
    results = []
    for item_ar in items_ar:
        # ترجمة الصنف
        item_en = GoogleTranslator(source='ar', target='en').translate(item_ar)
        # جلب القيم الغذائية
        data = fetch_nutrition(item_en)
        if data:
            nutrition = data[0]
            item_data = {
                "meal_id": meal_id,
                "food_name_ar": item_ar,
                "calories": nutrition['calories'],
                "protein": nutrition['protein_g'],
                "carbs": nutrition['carbohydrates_total_g'],
                "fat": nutrition['fat_total_g']
            }
            supabase.table("meal_items").insert(item_data).execute()
            results.append(item_data)
            
    return {"message": "Meal logged successfully", "items": results}

# --- قسم الاستبيان وحساب الأهداف (Mifflin-St Jeor) ---

@app.post("/calculate_goals")
async def calculate_goals(user_id: str, weight: float, height: float, age: int, gender: str, activity: str, goal: str):
    # حساب BMR
    if gender == "male":
        bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5
    else:
        bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161
        
    # معامل النشاط
    multipliers = {"sedentary": 1.2, "light": 1.375, "moderate": 1.55, "active": 1.725}
    tdee = bmr * multipliers.get(activity, 1.2)
    
    # تعديل السعرات حسب الهدف
    target_calories = tdee - 500 if goal == "lose" else tdee + 500 if goal == "gain" else tdee
    target_water = weight * 35 # مللمتر
    
    # تحديث البروفايل في Supabase
    supabase.table("profiles").update({
        "weight": weight,
        "height": height,
        "age": age,
        "gender": gender,
        "target_calories": int(target_calories),
        "target_water_ml": int(target_water)
    }).eq("id", user_id).execute()
    
    return {"target_calories": int(target_calories), "target_water_ml": int(target_water)}
