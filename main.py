import os, requests, json, re, logging
from fastapi import FastAPI, Form, Query, Request, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client
from dotenv import load_dotenv
from datetime import datetime

# --- إعدادات المراقبة ---
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()
app = FastAPI(title="Solean AI Fitness Backend")

# تفعيل CORS لضمان اتصال Zapp بالسيرفر بدون قيود
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# --- محرك Gemini AI المطور ---
def get_ai_nutrition_estimate(food_query):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={GEMINI_API_KEY}"
    
    # برومبت صارم لضمان الحصول على JSON فقط
    prompt = (
        f"Analyze the nutritional content of: '{food_query}'. "
        "Return ONLY a JSON object with these exact keys: "
        '{"cal": float, "prot": float, "carb": float, "fat": float, "weight": float}. '
        "Do not include any text before or after the JSON."
    )
    
    try:
        response = requests.post(url, json={"contents": [{"parts": [{"text": prompt}]}]}, timeout=10)
        response_json = response.json()
        raw_text = response_json['candidates'][0]['content']['parts'][0]['text']
        
        # تنظيف النص المستلم من Gemini (إزالة ```json وأي زوائد)
        clean_json_match = re.search(r'\{.*\}', raw_text, re.DOTALL)
        if clean_json_match:
            return json.loads(clean_json_match.group())
        else:
            raise ValueError("No valid JSON found in AI response")
            
    except Exception as e:
        logger.error(f"AI Error for '{food_query}': {e}")
        # نرجع أصفار بدلاً من 250 لنعرف أن هناك خلل في المفتاح أو التحليل
        return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}

# --- العمليات الأساسية ---
@app.post("/log_meal")
async def log_meal(user_id: str = Query(...), meal_type: str = Query(...), items_ar: str = Form(...)):
    # 1. تسجيل رأس الوجبة
    meal_res = supabase.table("meals").insert({"user_id": user_id, "meal_type": meal_type}).execute()
    meal_id = meal_res.data[0]['id']
    
    # 2. تحليل المحتوى عبر Gemini
    nutri = get_ai_nutrition_estimate(items_ar)
    
    # 3. تخزين القيم الحقيقية في Supabase
    payload = {
        "meal_id": meal_id,
        "food_name": items_ar,
        "calories": float(nutri.get('cal', 0)),
        "protein": float(nutri.get('prot', 0)),
        "carbs": float(nutri.get('carb', 0)),
        "fat": float(nutri.get('fat', 0)),
        "weight_grams": float(nutri.get('weight', 0))
    }
    supabase.table("meal_items").insert(payload).execute()
    return {"status": "success", "data": payload}

@app.get("/get_daily_intake")
async def get_daily_intake(user_id: str = Query(...)):
    try:
        # جلب أهداف المستخدم (أو قيم افتراضية)
        profile = supabase.table("profiles").select("*").eq("id", user_id).maybe_single().execute()
        target_cal = profile.data.get("target_calories", 2000) if profile.data else 2000
        
        # جلب وجبات اليوم فقط
        today = datetime.now().strftime("%Y-%m-%d")
        meals = supabase.table("meals").select("id").eq("user_id", user_id).gte("created_at", today).execute()
        meal_ids = [m['id'] for m in meals.data]
        
        items = supabase.table("meal_items").select("*").in_("meal_id", meal_ids).execute()
        
        totals = {
            "cal": sum(i['calories'] for i in items.data),
            "prot": sum(i['protein'] for i in items.data),
            "fat": sum(i['fat'] for i in items.data),
            "carb": sum(i['carbs'] for i in items.data)
        }
        return {"totals": totals, "targets": {"cal": target_cal, "prot": 165, "fat": 55, "carb": 113}}
    except Exception as e:
        logger.error(f"Intake Error: {e}")
        return {"totals": {"cal": 0, "prot": 0, "fat": 0, "carb": 0}, "targets": {"cal": 2000}}

@app.get("/get_overall_score")
async def get_overall_score(user_id: str = Query(...)):
    # حساب السكور بناءً على السعرات (مثال بسيط: نسبة الإنجاز من الهدف)
    data = await get_daily_intake(user_id)
    current = data['totals']['cal']
    target = data['targets']['cal']
    
    score = (current / target) * 100 if target > 0 else 0
    return {"score": min(int(score), 100)}

@app.post("/log_water")
async def log_water(user_id: str = Query(...), amount_ml: str = Form(...)):
    # تعديل بسيط لاستقبال Form data ليتوافق مع Flutter
    return supabase.table("water_logs").insert({"user_id": user_id, "amount_ml": int(amount_ml)}).execute()