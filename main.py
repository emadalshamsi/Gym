import os
import requests
import json
from fastapi import FastAPI, Form, Query
from supabase import create_client, Client
from deep_translator import GoogleTranslator
from dotenv import load_dotenv

# 1. تحميل الإعدادات
load_dotenv()

app = FastAPI()

# 2. إعداد الربط مع الخدمات
SUPABASE_URL: str = os.getenv("SUPABASE_URL")
SUPABASE_KEY: str = os.getenv("SUPABASE_ANON_KEY")
NINJAS_API_KEY: str = os.getenv("NINJAS_API_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# 3. دالة جلب البيانات الغذائية
def fetch_nutrition(food_name_en):
    try:
        api_url = f'https://api.api-ninjas.com/v1/nutrition?query={food_name_en}'
        response = requests.get(api_url, headers={'X-Api-Key': NINJAS_API_KEY}, timeout=5)
        if response.status_code == 200:
            return response.json()
        return []
    except Exception as e:
        print(f"Error fetching nutrition: {e}")
        return []

# 4. دالة تسجيل الوجبة (المعدلة للتوافق التام)
@app.post("/log_meal")
async def log_meal(
    user_id: str = Query(...), 
    meal_type: str = Query(...), 
    items_ar: str = Form(...) # يقبل النص من واجهة Swagger
):
    try:
        # تحويل المدخلات من نص (Form) إلى قائمة Python
        try:
            # نحاول معالجة النص إذا كان مرسلاً كـ ["بيض"]
            items_list = json.loads(items_ar.replace("'", '"'))
        except:
            # إذا فشل، نعتبره نصاً عادياً ونضعه في قائمة
            items_list = [items_ar.strip()]

        # أ. إنشاء سجل الوجبة الرئيسي في جدول meals
        meal_record = supabase.table("meals").insert({
            "user_id": user_id, 
            "meal_type": meal_type
        }).execute()
        
        if not meal_record.data:
            return {"status": "error", "message": "Could not create meal record in Supabase"}
            
        meal_id = meal_record.data[0]['id']
        added_items = []

        # ب. حلقة إضافة الأصناف لجدول meal_items
        for item_ar in items_list:
            # قيم افتراضية في حال فشل الترجمة أو الـ API
            calories, protein, carbs, fat = 0.0, 0.0, 0.0, 0.0
            
            try:
                # ترجمة من العربي للإنجليزي
                item_en = GoogleTranslator(source='ar', target='en').translate(item_ar)
                # جلب السعرات
                nutrition_data = fetch_nutrition(item_en)
                
                if nutrition_data:
                    top_result = nutrition_data[0]
                    calories = top_result.get('calories', 0.0)
                    protein = top_result.get('protein_g', 0.0)
                    carbs = top_result.get('carbohydrates_total_g', 0.0)
                    fat = top_result.get('fat_total_g', 0.0)
            except Exception as e:
                print(f"Skipping nutrition fetch for {item_ar}: {e}")

            # ج. الإدخال الفعلي في جدول meal_items (تأكد أن الاسم food_name)
            item_payload = {
                "meal_id": meal_id,
                "food_name": item_ar, # الاسم العربي كما هو في سوبابيز
                "calories": calories,
                "protein": protein,
                "carbs": carbs,
                "fat": fat
            }
            
            supabase.table("meal_items").insert(item_payload).execute()
            added_items.append(item_payload)

        return {
            "status": "success",
            "meal_id": meal_id,
            "items_count": len(added_items),
            "data": added_items
        }

    except Exception as e:
        return {"status": "error", "detail": str(e)}

# 5. دالة حساب الأهداف وتحديث البروفايل
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
        # معادلة Mifflin-St Jeor
        if gender.lower() == "male":
            bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5
        else:
            bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161
            
        # معاملات النشاط
        multipliers = {
            "sedentary": 1.2, 
            "light": 1.375, 
            "moderate": 1.55, 
            "active": 1.725
        }
        tdee = bmr * multipliers.get(activity.lower(), 1.2)
        
        # تعديل السعرات حسب الهدف
        if goal.lower() == "lose":
            target_calories = tdee - 500
        elif goal.lower() == "gain":
            target_calories = tdee + 500
        else:
            target_calories = tdee

        target_water = weight * 35 
        
        # تحديث أو إنشاء البروفايل (Upsert)
        supabase.table("profiles").upsert({
            "id": user_id,
            "weight": weight,
            "height": height,
            "age": age,
            "gender": gender,
            "target_calories": int(target_calories),
            "target_water_ml": int(target_water)
        }).execute()
        
        return {
            "status": "success",
            "target_calories": int(target_calories), 
            "target_water_ml": int(target_water)
        }
    except Exception as e:
        return {"status": "error", "detail": str(e)}