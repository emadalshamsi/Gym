import os, requests, json, re, logging
from fastapi import FastAPI, Form, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client
from dotenv import load_dotenv
from datetime import datetime

# إعدادات التسجيل لمراقبة الأخطاء في Render
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()
app = FastAPI(title="Solean AI Fitness")

# تفعيل CORS للسماح لـ Zapp بالاتصال (تجنب خطأ XMLHttpRequest)
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

# --- محرك التحليل الذكي ---
def get_ai_nutrition_estimate(food_query):
    """تحليل النص واستخراج البيانات الغذائية عبر Gemini"""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={GEMINI_API_KEY}"
    
    prompt = (
        f"Analyze the food: '{food_query}'. "
        "Return ONLY a JSON object with these keys: "
        '{"cal": float, "prot": float, "carb": float, "fat": float, "weight": float}. '
        "Be accurate and return only the JSON structure."
    )
    
    try:
        response = requests.post(url, json={"contents": [{"parts": [{"text": prompt}]}]}, timeout=10)
        res_data = response.json()
        raw_text = res_data['candidates'][0]['content']['parts'][0]['text']
        
        # تنظيف النص لضمان استخراج الـ JSON فقط
        clean_json = re.search(r'\{.*\}', raw_text, re.DOTALL).group()
        return json.loads(clean_json)
    except Exception as e:
        logger.error(f"Gemini Error for '{food_query}': {e}")
        # إذا فشل التحليل، نرسل أصفاراً لنعرف أن هناك مشكلة في الـ API Key أو الاتصال
        return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}

# --- 1. تسجيل الوجبات (Log Meal) ---
@app.post("/log_meal")
async def log_meal(user_id: str = Query(...), meal_type: str = Query(...), items_ar: str = Form(...)):
    # تسجيل الوجبة في جدول meals للحصول على ID
    meal_res = supabase.table("meals").insert({"user_id": user_id, "meal_type": meal_type}).execute()
    meal_id = meal_res.data[0]['id']
    
    # الحصول على التحليل من AI
    nutri = get_ai_nutrition_estimate(items_ar)
    
    # تخزين البيانات في جدول meal_items
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

# --- 2. جلب البيانات اليومية (Daily Intake) ---
@app.get("/get_daily_intake")
async def get_daily_intake(user_id: str = Query(...)):
    today = datetime.now().strftime("%Y-%m-%d")
    
    # جلب الوجبات المسجلة اليوم
    meals = supabase.table("meals").select("id").eq("user_id", user_id).gte("created_at", today).execute()
    meal_ids = [m['id'] for m in meals.data]
    
    # جلب تفاصيل العناصر وحساب المجاميع
    items = supabase.table("meal_items").select("*").in_("meal_id", meal_ids).execute()
    
    totals = {
        "cal": sum(i['calories'] for i in items.data),
        "prot": sum(i['protein'] for i in items.data),
        "carb": sum(i['carbs'] for i in items.data),
        "fat": sum(i['fat'] for i in items.data)
    }
    
    # أهداف افتراضية (يمكن جلبها مستقبلاً من جدول profiles)
    targets = {"cal": 2000, "prot": 165, "carb": 250, "fat": 70}
    
    return {"totals": totals, "targets": targets}

# --- 3. حساب السكور الإجمالي (Overall Score) ---
@app.get("/get_overall_score")
async def get_overall_score(user_id: str = Query(...)):
    data = await get_daily_intake(user_id)
    totals = data['totals']
    targets = data['targets']
    
    # حساب السكور بناءً على الالتزام بالسعرات (كمثال)
    if targets['cal'] == 0: return {"score": 0}
    
    # السكور هو نسبة مئوية لمدى اقترابك من هدف السعرات (بحد أقصى 100)
    score_percentage = (totals['cal'] / targets['cal']) * 100
    return {"score": min(int(score_percentage), 100)}

@app.post("/log_water")
async def log_water(user_id: str = Query(...), amount_ml: str = Form(...)):
    # لاستقبال Form data ليتوافق مع Flutter
    return supabase.table("water_logs").insert({"user_id": user_id, "amount_ml": int(amount_ml)}).execute()