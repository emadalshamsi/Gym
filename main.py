import os, requests, json, re, logging
from fastapi import FastAPI, Form, Query, Request, Body
from pydantic import BaseModel
from typing import Optional
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

@app.get("/test_gemini")
async def test_gemini(query: str = "2 boiled eggs"):
    """نقطة فحص لاختبار اتصال Gemini بشكل مباشر"""
    res, debug = get_ai_nutrition_estimate(query)
    return {"query": query, "result": res, "debug": debug}

# --- محرك التحليل الذكي ---
def get_ai_nutrition_estimate(food_query):
    """تحليل النص واستخراج البيانات الغذائية عبر Gemini"""
    if not GEMINI_API_KEY:
        logger.error("خطأ: GEMINI_API_KEY غير مضبوط!")
        return {"cal": 0, "prot": 0, "carb": 0, "fat": 0, "weight": 0}, {"error": "Key missing"}

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={GEMINI_API_KEY}"
    
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

# --- Pydantic Models for JSON Requests ---
class MealLogRequest(BaseModel):
    user_id: str
    meal_type: str
    items_ar: str
    date: Optional[str] = None

class WaterLogRequest(BaseModel):
    user_id: str
    amount_ml: int
    date: Optional[str] = None

class SleepLogRequest(BaseModel):
    user_id: str
    hours: float
    date: Optional[str] = None

class StepsLogRequest(BaseModel):
    user_id: str
    steps: int
    date: Optional[str] = None

class MealUpdateRequest(BaseModel):
    item_id: str
    updates: dict

class AlignPhotosRequest(BaseModel):
    img1_base64: str
    img2_base64: str

class GoalsUpdateRequest(BaseModel):
    user_id: str
    habit_goals: dict
    calorie_target: Optional[int] = None
    water_target: Optional[int] = None
    protein_target: Optional[int] = None
    carb_target: Optional[int] = None
    fat_target: Optional[int] = None

class BodyMeasurementsRequest(BaseModel):
    user_id: str
    gender: str = "male"
    unit: str = "cm"
    neck: Optional[float] = None
    shoulder: Optional[float] = None
    chest: Optional[float] = None
    biceps_r: Optional[float] = None
    biceps_l: Optional[float] = None
    forearms_r: Optional[float] = None
    forearms_l: Optional[float] = None
    waist: Optional[float] = None
    hips: Optional[float] = None
    thighs_r: Optional[float] = None
    thighs_l: Optional[float] = None
    calves_r: Optional[float] = None
    calves_l: Optional[float] = None

class ProgressPhoto(BaseModel):
    user_id: str
    photo_url: str
    side: str # 'front', 'side', 'back'
    created_at: Optional[str] = None

# --- 1. تسجيل الوجبات (Log Meal) ---
@app.post("/log_meal")
async def log_meal(data: MealLogRequest):
    user_id = data.user_id
    meal_type = data.meal_type
    items_ar = data.items_ar
    log_time = data.date if data.date else datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
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
            "weight_grams": float(nutri.get('weight', 0))
        }
        supabase.table("meal_items").insert(payload).execute()
        return {"status": "success", "data": payload}
    except Exception as e:
        logger.error(f"Log Meal Error: {e}")
        return {"status": "error", "message": str(e)}

# --- 1b. حذف وجبة (Delete Meal Item) ---
@app.delete("/delete_meal_item")
async def delete_meal_item(item_id: str = Query(...)):
    try:
        supabase.table("meal_items").delete().eq("id", item_id).execute()
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Delete Error: {e}")
        return {"status": "error", "message": str(e)}

# --- 1c. تحديث وجبة (Update Meal Item) ---
@app.post("/update_meal_item")
async def update_meal_item(data: MealUpdateRequest):
    item_id = data.item_id
    new_food = data.new_food
    try:
        nutri, _ = get_ai_nutrition_estimate(new_food)
        supabase.table("meal_items").update({
            "food_name": new_food,
            "calories": float(nutri.get('cal', 0)),
            "protein": float(nutri.get('prot', 0)),
            "carbs": float(nutri.get('carb', 0)),
            "fat": float(nutri.get('fat', 0)),
            "weight_grams": float(nutri.get('weight', 0)),
        }).eq("id", item_id).execute()
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Update Error: {e}")
        return {"status": "error", "message": str(e)}

# --- 2. تسجيل المياه (Log Water) ---
@app.post("/log_water")
async def log_water(data: WaterLogRequest):
    user_id = data.user_id
    amount_ml = data.amount_ml
    log_time = data.date if data.date else datetime.now().strftime("%Y-%m-%d %H:%M:%S")
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

# --- 4. تسجيل النوم (Log Sleep) ---
@app.post("/log_sleep")
async def log_sleep(data: SleepLogRequest):
    user_id = data.user_id
    hours = data.hours
    log_time = data.date if data.date else datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        payload = {
            "user_id": user_id, 
            "hours": float(hours),
            "created_at": log_time
        }
        res = supabase.table("sleep_logs").insert(payload).execute()
        return {"status": "success", "data": res.data}
    except Exception as e:
        logger.error(f"Log Sleep Error: {e}")
        return {"status": "error", "message": str(e)}

# --- 5. تسجيل الخطوات (Log Steps) ---
@app.post("/log_steps")
async def log_steps(data: StepsLogRequest):
    user_id = data.user_id
    steps = data.steps
    log_time = data.date if data.date else datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        payload = {
            "user_id": user_id, 
            "steps": int(steps),
            "created_at": log_time
        }
        res = supabase.table("steps_logs").insert(payload).execute()
        return {"status": "success", "data": res.data}
    except Exception as e:
        logger.error(f"Log Steps Error: {e}")
        return {"status": "error", "message": str(e)}

# --- 2b. تحديث الأهداف (Update Goals) ---
@app.post("/update_goals")
async def update_goals(data: GoalsUpdateRequest):
    try:
        payload = {"habit_goals": data.habit_goals}
        if data.calorie_target is not None:
            payload["daily_calorie_target"] = data.calorie_target
        if data.water_target is not None:
            payload["daily_water_target_ml"] = data.water_target
        if data.protein_target is not None:
            payload["daily_protein_target"] = data.protein_target
        if data.carb_target is not None:
            payload["daily_carb_target"] = data.carb_target
        if data.fat_target is not None:
            payload["daily_fat_target"] = data.fat_target
            
        supabase.table("profiles").update(payload).eq("id", data.user_id).execute()
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Update Goals Error: {e}")
        return {"status": "error", "message": str(e)}

# --- 2c. تحديث مقاسات الجسم (Update Body Measurements) ---
@app.post("/update_measurements")
async def update_measurements(data: BodyMeasurementsRequest):
    try:
        payload = data.dict(exclude={"user_id"})
        # إدراج سجل جديد لتتبع التاريخ
        supabase.table("body_measurements").insert({
            "user_id": data.user_id,
            **payload
        }).execute()
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Update Measurements Error: {e}")
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
            "water": profile.get("daily_water_target_ml", 2000),
            "habit_goals": profile.get("habit_goals", {})
        }
        
        # جلب أحدث مقاسات الجسم
        body_measurements = {}
        try:
            meas_res = supabase.table("body_measurements").select("*").eq("user_id", user_id).order("created_at", desc=True).limit(1).execute()
            if meas_res.data:
                body_measurements = meas_res.data[0]
        except Exception as e:
            logger.warning(f"Body Measurements error (possibly table missing): {e}")
        
        # جلب الوجبات
        meals = supabase.table("meals").select("id").eq("user_id", user_id).gte("created_at", target_date).lt("created_at", next_day).execute()
        meal_ids = [m['id'] for m in (meals.data if meals.data else [])]
        
        items_data = []
        if meal_ids:
            items_res = supabase.table("meal_items").select("*, meals(meal_type)").in_("meal_id", meal_ids).execute()
            items_data = items_res.data if items_res.data else []
        
        # جلب سجلات المياه
        water_res = supabase.table("water_logs").select("amount_ml").eq("user_id", user_id).gte("created_at", target_date).lt("created_at", next_day).execute()
        water_data = water_res.data if water_res.data else []
        water_total = sum(w['amount_ml'] for w in water_data)

        # جلب سجلات النوم
        sleep_res = supabase.table("sleep_logs").select("hours").eq("user_id", user_id).gte("created_at", target_date).lt("created_at", next_day).execute()
        sleep_data = sleep_res.data if sleep_res.data else []
        sleep_total = sum(s['hours'] for s in sleep_data)

        # جلب سجلات الخطوات
        steps_res = supabase.table("steps_logs").select("steps").eq("user_id", user_id).gte("created_at", target_date).lt("created_at", next_day).execute()
        steps_data = steps_res.data if steps_res.data else []
        steps_total = sum(s['steps'] for s in steps_data)
        
        totals = {
            "cal": sum((i.get('calories') or 0) for i in items_data),
            "prot": sum((i.get('protein') or 0) for i in items_data),
            "carb": sum((i.get('carbs') or 0) for i in items_data),
            "fat": sum((i.get('fat') or 0) for i in items_data),
            "water": water_total,
            "sleep": sleep_total,
            "steps": steps_total
        }

        items_list = [
            {
                "id": i.get("id", ""),
                "food_name": i.get("food_name", ""),
                "calories": i.get("calories") or 0,
                "protein": i.get("protein") or 0,
                "carbs": i.get("carbs") or 0,
                "fat": i.get("fat") or 0,
                "meal_type": i.get("meals", {}).get("meal_type", "Snack") if i.get("meals") else "Snack"
            }
            for i in items_data if (i.get("calories") or 0) > 0
        ]

        return {"totals": totals, "targets": targets, "profile": profile, "items": items_list, "body_measurements": body_measurements}
    except Exception as e:
        logger.error(f"Global Intake Error: {str(e)}")
        return {"error": str(e), "status": "failed"}

# --- 4. جلب إحصائيات السعرات والمياه (Stats) ---
@app.get("/get_stats")
async def get_stats(user_id: str = Query(...), days: int = Query(7)):
    try:
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days - 1)
        start_str = start_date.strftime("%Y-%m-%d")
        
        # 1. جلب إحصائيات السعرات
        meals_res = supabase.table("meals").select("id, created_at").eq("user_id", user_id).gte("created_at", start_str).execute()
        meals_data = meals_res.data if meals_res.data else []
        meal_ids = [m['id'] for m in meals_data]
        
        cal_map = { (start_date + timedelta(days=i)).strftime("%Y-%m-%d"): 0.0 for i in range(days) }

        if meal_ids:
            items_res = supabase.table("meal_items").select("calories, meal_id").in_("meal_id", meal_ids).execute()
            items_data = items_res.data if items_res.data else []
            meal_id_to_date = {m['id']: (m.get('created_at') or "")[:10] for m in meals_data}
            for item in items_data:
                date_key = meal_id_to_date.get(item['meal_id'])
                if date_key in cal_map:
                    cal_map[date_key] += float(item.get('calories') or 0)

        # 2. جلب إحصائيات المياه
        water_res = supabase.table("water_logs").select("amount_ml, created_at").eq("user_id", user_id).gte("created_at", start_str).execute()
        water_data_list = water_res.data if water_res.data else []
        
        water_map = { (start_date + timedelta(days=i)).strftime("%Y-%m-%d"): 0.0 for i in range(days) }
        for w in water_data_list:
            date_key = (w.get('created_at') or "")[:10]
            if date_key in water_map:
                water_map[date_key] += float(w['amount_ml'] or 0)

        # 3. جلب إحصائيات النوم
        sleep_res = supabase.table("sleep_logs").select("hours, created_at").eq("user_id", user_id).gte("created_at", start_str).execute()
        sleep_data_list = sleep_res.data if sleep_res.data else []
        sleep_map = { (start_date + timedelta(days=i)).strftime("%Y-%m-%d"): 0.0 for i in range(days) }
        for s in sleep_data_list:
            date_key = (s.get('created_at') or "")[:10]
            if date_key in sleep_map:
                sleep_map[date_key] += float(s['hours'] or 0)

        # 4. جلب إحصائيات الخطوات
        steps_res = supabase.table("steps_logs").select("steps, created_at").eq("user_id", user_id).gte("created_at", start_str).execute()
        steps_data_list = steps_res.data if steps_res.data else []
        steps_map = { (start_date + timedelta(days=i)).strftime("%Y-%m-%d"): 0.0 for i in range(days) }
        for st in steps_data_list:
            date_key = (st.get('created_at') or "")[:10]
            if date_key in steps_map:
                steps_map[date_key] += float(st['steps'] or 0)

        cal_result = [{"date": k, "value": v} for k, v in sorted(cal_map.items())]
        water_result = [{"date": k, "value": v} for k, v in sorted(water_map.items())]
        sleep_result = [{"date": k, "value": v} for k, v in sorted(sleep_map.items())]
        steps_result = [{"date": k, "value": v} for k, v in sorted(steps_map.items())]
        
        return {
            "status": "success", 
            "calories": cal_result,
            "water": water_result,
            "sleep": sleep_result,
            "steps": steps_result
        }
    except Exception as e:
        logger.error(f"Stats Error: {str(e)}")
        return {"error": str(e), "status": "failed"}


@app.post("/upload_progress_photo")
async def upload_progress_photo(data: ProgressPhoto):
    try:
        payload = {
            "user_id": data.user_id,
            "photo_url": data.photo_url,
            "side": data.side
        }
        if data.created_at:
            payload["created_at"] = data.created_at
            
        res = supabase.table("progress_photos").insert(payload).execute()
        return {"status": "success", "data": res.data[0] if res.data else None}
    except Exception as e:
        logger.error(f"Upload Photo Error: {str(e)}")
        return {"error": str(e), "status": "failed"}

@app.get("/get_progress_photos")
async def get_progress_photos(user_id: str = Query(...)):
    try:
        res = supabase.table("progress_photos").select("*").eq("user_id", user_id).order("created_at", desc=True).execute()
        return {"status": "success", "data": res.data}
    except Exception as e:
        logger.error(f"Get Photos Error: {str(e)}")
        return {"error": str(e), "status": "failed"}
@app.post("/align_photos")
async def align_photos(data: AlignPhotosRequest):
    """استخدام Gemini لمحاذاة صورتين بناءً على ملامح الجسم"""
    if not GEMINI_API_KEY:
        return {"error": "API Key missing", "status": "failed"}

    # تنظيف الـ Base64 (إزالة البادئة إن وجدت)
    def clean_b64(b64):
        if "," in b64: return b64.split(",")[1]
        return b64

    img1 = clean_b64(data.img1_base64)
    img2 = clean_b64(data.img2_base64)

    url = f"https://generativelanguage.googleapis.com/v1/models/gemini-1.5-flash:generateContent?key={GEMINI_API_KEY}"
    
    prompt = (
        "Analyze these two progress photos. Detect the precise [x, y] coordinates for: "
        "1. Nose, 2. Left Shoulder, 3. Right Shoulder in BOTH images. "
        "Coordinates must be normalized from 0 to 1000 (where 0,0 is top-left). "
        "Return ONLY a JSON object: "
        '{"img1": {"nose": [x,y], "l_sh": [x,y], "r_sh": [x,y]}, '
        '"img2": {"nose": [x,y], "l_sh": [x,y], "r_sh": [x,y]}}'
    )

    payload = {
        "contents": [{
            "parts": [
                {"text": prompt},
                {"inline_data": {"mime_type": "image/jpeg", "data": img1}},
                {"inline_data": {"mime_type": "image/jpeg", "data": img2}}
            ]
        }]
    }

    try:
        response = requests.post(url, json=payload, timeout=20)
        res_data = response.json()
        
        if 'candidates' not in res_data:
            error_msg = res_data.get('error', {}).get('message', 'Unknown Gemini Error')
            logger.error(f"Gemini API Error: {res_data}")
            return {"error": f"Gemini Error: {error_msg}", "status": "failed"}

        raw_text = res_data['candidates'][0]['content']['parts'][0]['text'].strip()
        
        match = re.search(r'(\{.*\})', raw_text, re.DOTALL)
        if not match: 
            logger.error(f"No JSON in AI response: {raw_text}")
            return {"error": "AI failed to return valid coordinates", "status": "failed"}
        
        pts = json.loads(match.group(1))
        
        # حساب المحاذاة (Align img2 to img1)
        # 1. Scale based on shoulder width
        w1 = ((pts['img1']['l_sh'][0] - pts['img1']['r_sh'][0])**2 + (pts['img1']['l_sh'][1] - pts['img1']['r_sh'][1])**2)**0.5
        w2 = ((pts['img2']['l_sh'][0] - pts['img2']['r_sh'][0])**2 + (pts['img2']['l_sh'][1] - pts['img2']['r_sh'][1])**2)**0.5
        
        if w2 == 0: return {"error": "Landmarks not found", "status": "failed"}
        scale = w1 / w2
        
        # 2. Offset based on nose position
        # We want: img2_nose * scale + offset = img1_nose
        dx = pts['img1']['nose'][0] - (pts['img2']['nose'][0] * scale)
        dy = pts['img1']['nose'][1] - (pts['img2']['nose'][1] * scale)

        return {
            "status": "success",
            "alignment": {
                "scale": scale,
                "dx": dx / 1000.0, # Convert back to normalized 0-1 for Flutter
                "dy": dy / 1000.0
            }
        }
    except Exception as e:
        logger.error(f"Align Error: {e}")
        return {"error": str(e), "status": "failed"}

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
