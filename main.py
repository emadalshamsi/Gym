import os
import requests
import json
from fastapi import FastAPI, Form, Query
from supabase import create_client, Client
from deep_translator import GoogleTranslator
from dotenv import load_dotenv

# تحميل الإعدادات
load_dotenv()

app = FastAPI()

# إعداد الربط
SUPABASE_URL: str = os.getenv("SUPABASE_URL")
SUPABASE_KEY: str = os.getenv("SUPABASE_ANON_KEY")
NINJAS_API_KEY: str = os.getenv("NINJAS_API_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

def fetch_nutrition(food_name_en):
    try:
        api_url = f'https://api.api-ninjas.com/v1/nutrition?query={food_name_en}'
        # تأكد أن اسم المتغير هنا يطابق تماماً ما كتبت في Render
        response = requests.get(api_url, headers={'X-Api-Key': NINJAS_API_KEY}, timeout=5)
        
        # هذه السطور ستطبع لنا في سجلات Render ماذا يحدث بالضبط
        print(f"--- API DEBUG START ---")
        print(f"Query: {food_name_en}")
        print(f"Status Code: {response.status_code}")
        print(f"Response Text: {response.text}")
        print(f"--- API DEBUG END ---")
        
        if response.status_code == 200:
            return response.json()
        return []
    except Exception as e:
        print(f"Connection Error: {e}")
        return []

@app.post("/log_meal")
async def log_meal(
    user_id: str = Query(...), 
    meal_type: str = Query(...), 
    items_ar: str = Form(...) 
):
    try:
        # معالجة المدخلات القادمة من Swagger
        try:
            items_list = json.loads(items_ar.replace("'", '"'))
        except:
            items_list = [items_ar.strip()]

        # 1. تسجيل الوجبة في جدول meals
        meal_record = supabase.table("meals").insert({
            "user_id": user_id, 
            "meal_type": meal_type
        }).execute()
        
        if not meal_record.data:
            return {"status": "error", "message": "Failed to create meal"}
            
        meal_id = meal_record.data[0]['id']
        added_items = []

        # 2. إضافة الأصناف لجدول meal_items
        for item_ar in items_list:
            # قيم افتراضية رقمية لضمان عدم حدوث خطأ double precision
            cal, prot, carb, fat = 0.0, 0.0, 0.0, 0.0
            
            try:
                # الترجمة (جوجل ترانسليت مجاني ومستقر)
                item_en = GoogleTranslator(source='ar', target='en').translate(item_ar)
                
                # جلب السعرات وفحصها بدقة
                nutrition_data = fetch_nutrition(item_en)
                if nutrition_data:
                    res = nutrition_data[0]
                    # تحويل القيم لأرقام float لضمان التوافق مع قاعدة البيانات
                    cal = float(res.get('calories', 0.0))
                    prot = float(res.get('protein_g', 0.0))
                    carb = float(res.get('carbohydrates_total_g', 0.0))
                    fat = float(res.get('fat_total_g', 0.0))
            except:
                pass # في حال فشل الـ API، نعتمد القيم الصفرية لضمان الحفظ

            # تجهيز البيانات (استخدام food_name كما هو في سوبابيز)
            item_payload = {
                "meal_id": meal_id,
                "food_name": item_ar, 
                "calories": cal,
                "protein": prot,
                "carbs": carb,
                "fat": fat
            }
            
            supabase.table("meal_items").insert(item_payload).execute()
            added_items.append(item_payload)

        return {"status": "success", "meal_id": meal_id, "items": added_items}

    except Exception as e:
        return {"status": "error", "detail": str(e)}

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