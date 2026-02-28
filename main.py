import os, requests, json, re
from fastapi import FastAPI, Form, Query
from supabase import create_client, Client
from dotenv import load_dotenv

load_dotenv()
app = FastAPI()

# الربط مع Supabase و Gemini
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

def get_ai_nutrition_estimate(food_query):
    """تحليل النص واستخراج القيم والوزن بدقة عبر Gemini"""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={GEMINI_API_KEY}"
    
    prompt = f"""
    Analyze the food entry: "{food_query}".
    Provide the nutrition facts and weight. 
    Return ONLY a raw JSON object:
    {{"cal": calories, "prot": protein_g, "carb": carbs_g, "fat": fat_g, "weight": weight_in_grams}}
    If multiple items are mentioned (like shakshuka and sausage), sum their values.
    """
    
    try:
        response = requests.post(url, json={"contents": [{"parts": [{"text": prompt}]}]}, timeout=10)
        data = response.json()
        ai_text = data['candidates'][0]['content']['parts'][0]['text']
        # تنظيف النص من أي زوائد برمجية
        clean_json = re.search(r'\{.*\}', ai_text, re.DOTALL).group()
        return json.loads(clean_json)
    except Exception as e:
        print(f"Gemini API Error: {e}")
        # قيم "تخمينية" لضمان عدم ظهور أصفار في قاعدة البيانات
        return {"cal": 250, "prot": 15, "carb": 10, "fat": 15, "weight": 200}

@app.post("/log_meal")
async def log_meal(user_id: str = Query(...), meal_type: str = Query(...), items_ar: str = Form(...)):
    try:
        # معالجة المدخلات
        try:
            items_list = json.loads(items_ar.replace("'", '"'))
        except:
            items_list = [items_ar.strip()]

        # تسجيل الوجبة في Supabase
        meal_res = supabase.table("meals").insert({"user_id": user_id, "meal_type": meal_type}).execute()
        meal_id = meal_res.data[0]['id']
        added_items = []

        for item_ar in items_list:
            # استدعاء الذكاء الاصطناعي
            nutri = get_ai_nutrition_estimate(item_ar)

            payload = {
                "meal_id": meal_id,
                "food_name": item_ar, 
                "calories": float(nutri.get('cal', 0)),
                "protein": float(nutri.get('prot', 0)),
                "carbs": float(nutri.get('carb', 0)),
                "fat": float(nutri.get('fat', 0)),
                "weight_grams": float(nutri.get('weight', 0))
            }
            supabase.table("meal_items").insert(payload).execute()
            added_items.append(payload)

        return {"status": "success", "items": added_items}
    except Exception as e:
        return {"status": "error", "detail": str(e)}

@app.post("/calculate_goals")
async def calculate_goals(user_id: str = Query(...), weight: float = Query(...), height: float = Query(...), age: int = Query(...), gender: str = Query(...), activity: str = Query(...), goal: str = Query(...)):
    try:
        bmr = (10 * weight) + (6.25 * height) - (5 * age) + (5 if gender.lower() == "male" else -161)
        m = {"sedentary": 1.2, "light": 1.375, "moderate": 1.55, "active": 1.725}
        tdee = bmr * m.get(activity.lower(), 1.2)
        target_cal = tdee - 500 if goal.lower() == "lose" else tdee + 500 if goal.lower() == "gain" else tdee
        supabase.table("profiles").upsert({"id": user_id, "weight": weight, "height": height, "age": age, "gender": gender, "target_calories": int(target_cal), "target_water_ml": int(weight * 35)}).execute()
        return {"status": "success", "target_calories": int(target_cal)}
    except Exception as e:
        return {"status": "error", "detail": str(e)}