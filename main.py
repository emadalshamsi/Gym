import os, requests, json
from fastapi import FastAPI, Form, Query
from supabase import create_client, Client
from dotenv import load_dotenv

# 1. تحميل الإعدادات
load_dotenv()
app = FastAPI()

# 2. الربط مع سوبابيز وجيمناي
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

def get_ai_nutrition_estimate(food_query):
    """تحليل النص بواسطة Gemini لاستخراج القيم الغذائية والوزن"""
    prompt = f"""
    Analyze this food entry: "{food_query}".
    Estimate the nutrition and extract the weight if mentioned.
    Return ONLY a JSON object with these exact keys: 
    "cal" (calories), "prot" (protein g), "carb" (carbs g), "fat" (fat g), "weight" (weight in grams).
    
    Notes:
    - If weight is not mentioned, estimate a logical weight based on the portion described.
    - Return numbers only.
    - Example for "100g Shakshuka": {{"cal": 150, "prot": 8, "carb": 12, "fat": 10, "weight": 100}}
    """
    
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={GEMINI_API_KEY}"
    headers = {'Content-Type': 'application/json'}
    payload = {
        "contents": [{"parts": [{"text": prompt}]}]
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=10)
        result = response.json()
        ai_text = result['candidates'][0]['content']['parts'][0]['text']
        # تنظيف النص من أي علامات تنسيق مثل ```json
        clean_json = ai_text.replace("```json", "").replace("```", "").strip()
        return json.loads(clean_json)
    except Exception as e:
        print(f"AI Error: {e}")
        return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}

@app.post("/log_meal")
async def log_meal(
    user_id: str = Query(...), 
    meal_type: str = Query(...), 
    items_ar: str = Form(...)
):
    try:
        # معالجة المدخلات
        try:
            items_list = json.loads(items_ar.replace("'", '"'))
        except:
            items_list = [items_ar.strip()]

        # إنشاء سجل الوجبة
        meal_record = supabase.table("meals").insert({
            "user_id": user_id, 
            "meal_type": meal_type
        }).execute()
        
        if not meal_record.data:
            return {"status": "error", "message": "Failed to connect to Supabase"}
            
        meal_id = meal_record.data[0]['id']
        added_items = []

        for item_ar in items_list:
            # تحليل الصنف واستخراج الوزن والقيم الغذائية
            nutri = get_ai_nutrition_estimate(item_ar)

            payload = {
                "meal_id": meal_id,
                "food_name": item_ar, 
                "calories": float(nutri.get('cal', 0)),
                "protein": float(nutri.get('prot', 0)),
                "carbs": float(nutri.get('carb', 0)),
                "fat": float(nutri.get('fat', 0)),
                "weight_grams": float(nutri.get('weight', 0)) # إضافة الوزن المستخرج
            }
            
            supabase.table("meal_items").insert(payload).execute()
            added_items.append(payload)

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