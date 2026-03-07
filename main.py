import os, requests, json, re, logging
from fastapi import FastAPI, Form, Query, Request
from supabase import create_client, Client
from dotenv import load_dotenv
from datetime import datetime

# --- إعدادات المراقبة (لرؤية ما يحدث لحظياً) ---
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 1. إعداد البيئة والربط
load_dotenv()
app = FastAPI(title="AI Fitness App Backend")

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# --- Middleware لمراقبة كل حركة على السيرفر ---
@app.middleware("http")
async def log_requests(request: Request, call_next):
    logger.info(f"إجراء طلب: {request.method} على {request.url}")
    response = await call_next(request)
    logger.info(f"حالة الرد: {response.status_code}")
    return response

# --- العقل المدبر: محرك Gemini AI ---
def get_ai_nutrition_estimate(food_query):
    """تحليل النص التراثي واستخراج القيم الغذائية بدقة"""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={GEMINI_API_KEY}"
    prompt = f"""
    Analyze the food entry: "{food_query}".
    Estimate nutrition and weight. Return ONLY a raw JSON: 
    {{"cal": calories, "prot": protein_g, "carb": carbs_g, "fat": fat_g, "weight": weight_in_grams}}
    Sum values if multiple items are mentioned. Estimate weight logically if not stated.
    """
    try:
        response = requests.post(url, json={"contents": [{"parts": [{"text": prompt}]}]}, timeout=10)
        data = response.json()
        ai_text = data['candidates'][0]['content']['parts'][0]['text']
        match = re.search(r'\{.*\}', ai_text, re.DOTALL)
        if match:
            return json.loads(match.group())
        raise ValueError("No JSON found")
    except Exception as e:
        logger.error(f"خطأ في تحليل Gemini: {e}")
        return {"cal": 250, "prot": 15, "carb": 10, "fat": 15, "weight": 200} # قيم افتراضية آمنة

# --- 1. مسارات التغذية (Nutrition) ---
@app.post("/log_meal")
async def log_meal(user_id: str = Query(...), meal_type: str = Query(...), items_ar: str = Form(...)):
    try:
        try:
            items_list = json.loads(items_ar.replace("'", '"'))
        except:
            items_list = [items_ar.strip()]

        meal_res = supabase.table("meals").insert({"user_id": user_id, "meal_type": meal_type}).execute()
        meal_id = meal_res.data[0]['id']
        added_items = []

        for item_ar in items_list:
            nutri = get_ai_nutrition_estimate(item_ar)
            payload = {
                "meal_id": meal_id, "food_name": item_ar, 
                "calories": float(nutri.get('cal', 0)), "protein": float(nutri.get('prot', 0)),
                "carbs": float(nutri.get('carb', 0)), "fat": float(nutri.get('fat', 0)),
                "weight_grams": float(nutri.get('weight', 0))
            }
            supabase.table("meal_items").insert(payload).execute()
            added_items.append(payload)
        return {"status": "success", "items": added_items}
    except Exception as e:
        return {"status": "error", "detail": str(e)}

@app.get("/get_daily_intake")
async def get_daily_intake(user_id: str = Query(...)):
    try:
        profile = supabase.table("profiles").select("*").eq("id", user_id).single().execute()
        targets = {"cal": profile.data.get("target_calories", 2000), "prot": 165.0, "fat": 55.0, "carb": 113.0}
        
        today = datetime.now().strftime("%Y-%m-%d")
        meals = supabase.table("meals").select("id").eq("user_id", user_id).gte("created_at", today).execute()
        meal_ids = [m['id'] for m in meals.data]
        
        items = supabase.table("meal_items").select("*").in_("meal_id", meal_ids).execute()
        totals = {"cal": 0, "prot": 0, "fat": 0, "carb": 0}
        for i in items.data:
            totals["cal"] += i.get("calories", 0); totals["prot"] += i.get("protein", 0)
            totals["fat"] += i.get("fat", 0); totals["carb"] += i.get("carbs", 0)

        return {"status": "success", "data": totals, "targets": targets}
    except Exception as e:
        return {"status": "error", "detail": str(e)}

# --- 2. مسارات الماء (Water) ---
@app.post("/log_water")
async def log_water(user_id: str = Query(...), amount_ml: int = Query(...)):
    return supabase.table("water_logs").insert({"user_id": user_id, "amount_ml": amount_ml}).execute()

@app.get("/get_water_status")
async def get_water_status(user_id: str = Query(...)):
    profile = supabase.table("profiles").select("target_water_ml").eq("id", user_id).single().execute()
    today = datetime.now().strftime("%Y-%m-%d")
    logs = supabase.table("water_logs").select("amount_ml").eq("user_id", user_id).gte("created_at", today).execute()
    total = sum([l['amount_ml'] for l in logs.data])
    return {"current": total, "target": profile.data.get("target_water_ml", 2500)}

# --- 3. مسارات التمارين (Workouts) ---
@app.post("/log_workout")
async def log_workout(user_id: str = Query(...), workout_name: str = Form(...), duration_min: int = Form(...)):
    return supabase.table("workouts").insert({"user_id": user_id, "workout_name": workout_name, "duration_min": duration_min}).execute()

# --- 4. لوحة النتائج (Dashboard) ---
@app.get("/get_overall_score")
async def get_overall_score(user_id: str = Query(...)):
    try:
        today = datetime.now().strftime("%Y-%m-%d")
        intake = await get_daily_intake(user_id)
        nutrition_score = min((intake['data']['cal'] / intake['targets']['cal']) * 50, 50) if intake['targets']['cal'] > 0 else 0

        water = await get_water_status(user_id)
        water_score = min((water['current'] / water['target']) * 25, 25) if water['target'] > 0 else 0

        workouts = supabase.table("workouts").select("duration_min").eq("user_id", user_id).gte("created_at", today).execute()
        total_work = sum([w['duration_min'] for w in workouts.data])
        workout_score = min((total_work / 45) * 25, 25) # الهدف 45 دقيقة

        total = int(nutrition_score + water_score + workout_score)
        return {"overall_score": total, "display": f"{total}/100"}
    except:
        return {"overall_score": 0}

@app.post("/calculate_goals")
async def calculate_goals(user_id: str = Query(...), weight: float = Query(...), height: float = Query(...), age: int = Query(...), gender: str = Query(...), activity: str = Query(...), goal: str = Query(...)):
    bmr = (10 * weight) + (6.25 * height) - (5 * age) + (5 if gender.lower() == "male" else -161)
    tdee = bmr * {"sedentary": 1.2, "light": 1.375, "moderate": 1.55, "active": 1.725}.get(activity.lower(), 1.2)
    target_cal = tdee - 500 if goal.lower() == "lose" else tdee + 500 if goal.lower() == "gain" else tdee
    return supabase.table("profiles").upsert({"id": user_id, "weight": weight, "height": height, "age": age, "gender": gender, "target_calories": int(target_cal), "target_water_ml": int(weight * 35)}).execute()