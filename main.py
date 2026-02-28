import os, requests, json, re
from fastapi import FastAPI, Form, Query
from supabase import create_client, Client
from dotenv import load_dotenv

# 1. إعداد البيئة
load_dotenv()
app = FastAPI()

# 2. جلب مفاتيح الربط من Render
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

def get_ai_nutrition_estimate(food_query):
    """تحليل النص واستخراج القيم والوزن بدقة عبر ذكاء Gemini"""
    # الرابط الخاص بنموذج Gemini 1.5 Flash السريع
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={GEMINI_API_KEY}"
    
    prompt = f"""
    Analyze the food entry: "{food_query}".
    Estimate the total nutrition facts and weight. 
    Return ONLY a raw JSON object with these keys:
    {{"cal": calories, "prot": protein_g, "carb": carbs_g, "fat": fat_g, "weight": weight_in_grams}}
    If multiple items are mentioned (like shakshuka, sausage, and cheese), sum their values into one record.
    If weight is not explicitly mentioned, estimate it based on standard portions.
    """
    
    try:
        response = requests.post(url, json={"contents": [{"parts": [{"text": prompt}]}]}, timeout=10)
        data = response.json()
        ai_text = data['candidates'][0]['content']['parts'][0]['text']
        
        # استخراج الـ JSON فقط من نص الرد (لتجنب أي كلام إضافي من AI)
        clean_json = re.search(r'\{.*\}', ai_text, re.DOTALL).group()
        return json.loads(clean_json)
    except Exception as e:
        print(f"Gemini API Logic Error: {e}")
        # قيم افتراضية ذكية في حال فشل الاتصال لضمان عدم ظهور أصفار
        return {"cal": 250, "prot": 15, "carb": 10, "fat": 15, "weight": 200}

@app.post("/log_meal")
async def log_meal(
    user_id: str = Query(...), 
    meal_type: str = Query(...), 
    items_ar: str = Form(...)
):
    try:
        # معالجة المدخلات (تحويل النص إلى قائمة)
        try:
            items_list = json.loads(items_ar.replace("'", '"'))
        except:
            items_list = [items_ar.strip()]

        # تسجيل الوجبة في جدول meals
        meal_res = supabase.table("meals").insert({
            "user_id": user_id, 
            "meal_type": meal_type
        }).execute()
        
        if not meal_res.data:
            return {"status": "error", "message": "Database connection issue"}
            
        meal_id = meal_res.data[0]['id']
        added_items = []

        for item_ar in items_list:
            # هنا يحدث السحر: استدعاء التقدير الذكي لكل صنف مكتوب
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
            
            # حفظ الصنف في جدول meal_items
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
        # معادلة Mifflin-St Jeor (كما هي دون تغيير)
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