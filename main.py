import os, requests, json, re, logging
from fastapi import FastAPI, Form, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client
from dotenv import load_dotenv
from datetime import datetime, timedelta

# إعدادات التسجيل لمراقبة الأخطاء في Render
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()
app = FastAPI(title="Solean AI Fitness")

# تفعيل CORS للسماح لـ Zapp بالاتصال (تجنب خطأ XMLHttpRequest)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health_check():
    """نقطة فحص للتأكد من أن السيرفر يعمل"""
    return {"status": "online", "time": datetime.now().isoformat()}

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# --- محرك التحليل الذكي ---
def get_ai_nutrition_estimate(food_query):
    """تحليل النص واستخراج البيانات الغذائية عبر Gemini"""
    if not GEMINI_API_KEY:
        logger.error("خطأ: GEMINI_API_KEY غير مضبوط!")
        return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}, {"error": "Key missing"}

    # استعادة نسخة الموديل التي كانت تعمل بشكل سليم
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={GEMINI_API_KEY}"
    
    prompt = (
        f"Analyze the nutritional content of: '{food_query}'. "
        "Return ONLY a pure JSON object with these exact keys: "
        '{"cal": float, "prot": float, "carb": float, "fat": float, "weight": float}. '
        "Be extremely accurate. If multiple items are mentioned, sum their values. "
    )
    
    try:
        response = requests.post(url, json={"contents": [{"parts": [{"text": prompt}]}]}, timeout=15)
        if response.status_code != 200:
            return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}, {"error": response.text}

        res_data = response.json()
        raw_text = res_data['candidates'][0]['content']['parts'][0]['text'].strip()
        
        clean_json_match = re.search(r'(\{.*\})', raw_text, re.DOTALL)
        if clean_json_match:
            data = json.loads(clean_json_match.group(1))
            return data, {}
        return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}, {"error": "JSON not found"}
            
    except Exception as e:
        logger.error(f"Gemini Error: {e}")
        return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}, {"error": str(e)}

# --- 1. تسجيل الوجبات (Log Meal) ---
@app.post("/log_meal")
async def log_meal(user_id: str = Query(...), meal_type: str = Query(...), items_ar: str = Form(...), date: str = Form(None)):
    log_time = date if date else datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    logger.info(f"Logging meal: {meal_type} for {user_id} at {log_time}")
    
    try:
        meal_res = supabase.table("meals").insert({
            "user_id": user_id, 
            "meal_type": meal_type,
            "created_at": log_time
        }).execute()
        meal_id = meal_res.data[0]['id']
        
        nutri, _ = get_ai_nutrition_estimate(items_ar)
        
        payload = {
            "meal_id": meal_id,
            "food_name": items_ar,
            "calories": float(nutri.get('cal', 0)),
            "protein": float(nutri.get('prot', 0)),
            "carbs": float(nutri.get('carb', 0)),
            "fat": float(nutri.get('fat', 0)),
            "weight_grams": float(nutri.get('weight', 0)),
            "created_at": log_time
        }
        supabase.table("meal_items").insert(payload).execute()
        return {"status": "success", "data": payload}
    except Exception as e:
        logger.error(f"Log Meal Error: {e}")
        return {"status": "error", "message": str(e)}

# --- 2. تسجيل المياه (Log Water) ---
@app.post("/log_water")
async def log_water(user_id: str = Query(...), amount_ml: str = Form(...), date: str = Form(None)):
    log_time = date if date else datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    logger.info(f"Logging water: {amount_ml}ml for {user_id} at {log_time}")
    try:
        data = {
            "user_id": user_id, 
            "amount_ml": int(amount_ml),
            "created_at": log_time
        }
        res = supabase.table("water_logs").insert(data).execute()
        return {"status": "success", "data": res.data}
    except Exception as e:
        logger.error(f"Log Water Error: {e}")
        return {"status": "error", "message": str(e)}

# --- 3. جلب البيانات اليومية (Daily Intake) ---
@app.get("/get_daily_intake")
async def get_daily_intake(user_id: str = Query(...), date: str = Query(None)):
    try:
        target_date = date if date else datetime.now().strftime("%Y-%m-%d")
        current_dt = datetime.strptime(target_date, "%Y-%m-%d")
        next_day = (current_dt + timedelta(days=1)).strftime("%Y-%m-%d")
        
        # جلب أهداف المستخدم
        profile = {}
        prof_res = supabase.table("profiles").select("*").eq("id", user_id).execute()
        if prof_res.data:
            profile = prof_res.data[0]

        targets = {
            "cal": profile.get("daily_calorie_target", 2000),
            "prot": profile.get("daily_protein_target", 150),
            "carb": profile.get("daily_carb_target", 250),
            "fat": profile.get("daily_fat_target", 70),
            "water": profile.get("daily_water_target_ml", 2000)
        }
        
        # جلب الوجبات وتفاصيلها
        meals = supabase.table("meals").select("id").eq("user_id", user_id).gte("created_at", target_date).lt("created_at", next_day).execute()
        meal_ids = [m['id'] for m in (meals.data if meals.data else [])]
        
        items_data = []
        if meal_ids:
            items_res = supabase.table("meal_items").select("*").in_("meal_id", meal_ids).execute()
            items_data = items_res.data if items_res.data else []
        
        # جلب سجلات المياه
        water_res = supabase.table("water_logs").select("amount_ml").eq("user_id", user_id).gte("created_at", target_date).lt("created_at", next_day).execute()
        water_data = water_res.data if water_res.data else []
        water_total = sum(w['amount_ml'] for w in water_data)
        
        totals = {
            "cal": sum(i.get('calories', 0) for i in items_data),
            "prot": sum(i.get('protein', 0) for i in items_data),
            "carb": sum(i.get('carbs', 0) for i in items_data),
            "fat": sum(i.get('fat', 0) for i in items_data),
            "water": water_total
        }
        
        return {"totals": totals, "targets": targets, "profile": profile}
    except Exception as e:
        logger.error(f"Global Intake Error: {str(e)}")
        return {"error": str(e), "status": "failed"}