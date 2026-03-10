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
    debug_info: dict = {
        "key_found": bool(GEMINI_API_KEY),
        "status_code": None,
        "error": None,
        "raw_text": None,
        "raw_json": None
    }
    
    if not GEMINI_API_KEY:
        logger.error("خطأ: GEMINI_API_KEY غير مضبوط!")
        return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}, debug_info

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={GEMINI_API_KEY}"
    
    prompt = (
        f"Analyze the nutritional content of: '{food_query}'. "
        "Return ONLY a pure JSON object with these exact keys: "
        '{"cal": float, "prot": float, "carb": float, "fat": float, "weight": float}. '
        "Be extremely accurate. If multiple items are mentioned, sum their values. "
    )
    
    try:
        response = requests.post(url, json={"contents": [{"parts": [{"text": prompt}]}]}, timeout=15)
        debug_info["status_code"] = response.statusCode if hasattr(response, 'statusCode') else response.status_code
        
        if response.status_code != 200:
            debug_info["error"] = response.text
            return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}, debug_info

        res_data = response.json()
        if 'candidates' not in res_data or not res_data['candidates']:
            debug_info["error"] = "No candidates returned (Safety filter?)"
            debug_info["raw_json"] = res_data
            return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}, debug_info

        raw_text = res_data['candidates'][0]['content']['parts'][0]['text'].strip()
        debug_info["raw_text"] = raw_text
        
        clean_json_match = re.search(r'(\{.*\})', raw_text, re.DOTALL)
        if clean_json_match:
            data = json.loads(clean_json_match.group(1))
            return data, debug_info
        else:
            debug_info["error"] = "JSON not found in text"
            return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}, debug_info
            
    except Exception as e:
        debug_info["error"] = str(e)
        logger.error(f"Gemini Error for '{food_query}': {e}")
        return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}, debug_info

@app.get("/test_gemini")
async def test_gemini(query: str = "4 boiled eggs"):
    """نقطة فحص لاختبار اتصال Gemini بشكل مباشر مع تفاصيل فنية"""
    res, debug = get_ai_nutrition_estimate(query)
    return {"query": query, "result": res, "debug": debug}

@app.get("/list_models")
async def list_models():
    """قائمة الموديلات المتاحة لهذا المفتاح للتأكد من المسميات"""
    if not GEMINI_API_KEY:
        return {"error": "API Key missing"}
    
    url = f"https://generativelanguage.googleapis.com/v1beta/models?key={GEMINI_API_KEY}"
    try:
        response = requests.get(url)
        return response.json()
    except Exception as e:
        return {"error": str(e)}

@app.get("/test_water")
async def test_water(user_id: str = "6ec22654-069a-4ab1-8535-3ac66e0b5047"):
    """اختبار سريع لاتصال جدول المياه"""
    try:
        res = supabase.table("water_logs").select("*").eq("user_id", user_id).limit(1).execute()
        return {"status": "success", "data": res.data}
    except Exception as e:
        return {"status": "error", "message": str(e)}




# --- 1. تسجيل الوجبات (Log Meal) ---
@app.post("/log_meal")
async def log_meal(user_id: str = Query(...), meal_type: str = Query(...), items_ar: str = Form(...)):
    # تسجيل الوجبة في جدول meals للحصول على ID
    meal_res = supabase.table("meals").insert({"user_id": user_id, "meal_type": meal_type}).execute()
    meal_id = meal_res.data[0]['id']
    
    # الحصول على التحليل من AI
    nutri, _ = get_ai_nutrition_estimate(items_ar)

    
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
    
    # جلب أهداف المستخدم من جدول profiles
    profile = {}
    try:
        prof_res = supabase.table("profiles").select("*").eq("id", user_id).execute()
        if prof_res.data:
            profile = prof_res.data[0]
    except Exception as e:
        logger.error(f"Error fetching profile: {e}")

    # أهداف افتراضية إذا لم يوجد ملف شخصي
    targets = {
        "cal": profile.get("daily_calorie_target", 2000),
        "prot": profile.get("daily_protein_target", 150),
        "carb": profile.get("daily_carb_target", 250),
        "fat": profile.get("daily_fat_target", 70)
    }
    
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
    
    return {"totals": totals, "targets": targets, "profile": profile}

@app.get("/get_profile")
async def get_profile(user_id: str = Query(...)):
    """جلب بيانات الملف الشخصي"""
    try:
        res = supabase.table("profiles").select("*").eq("id", user_id).execute()
        if res.data:
            return {"status": "success", "data": res.data[0]}
        return {"status": "error", "message": "Profile not found"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

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
    """تسجيل شرب المياه مع التحقق من صحة البيانات"""
    logger.info(f"Log Water Request: user={user_id}, amount={amount_ml}")
    try:
        data = {"user_id": user_id, "amount_ml": int(amount_ml)}
        res = supabase.table("water_logs").insert(data).execute()
        logger.info(f"Water Log Success: {res.data}")
        return {"status": "success", "data": data}
    except Exception as e:
        logger.error(f"Water Log Error: {str(e)}")
        return {"status": "error", "message": str(e)}