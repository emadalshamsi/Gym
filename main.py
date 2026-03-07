import os, requests, json, re, logging
from fastapi import FastAPI, Form, Query, Request, UploadFile, File
from supabase import create_client, Client
from dotenv import load_dotenv
from datetime import datetime
from fastapi.middleware.cors import CORSMiddleware

# --- إعدادات المراقبة ---
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()
app = FastAPI(title="AI Fitness App Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)



SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

@app.get("/")
async def root():
    return {"status": "alive", "message": "Gym App Backend is running"}

# --- Middleware لمراقبة الطلبات ---

@app.middleware("http")
async def log_requests(request: Request, call_next):
    logger.info(f"Request: {request.method} {request.url}")
    response = await call_next(request)
    return response

# --- محرك Gemini AI للتغذية ---
def get_ai_nutrition_estimate(food_query):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={GEMINI_API_KEY}"
    prompt = f'Analyze: "{food_query}". Return ONLY JSON: {{"cal": calories, "prot": protein, "carb": carbs, "fat": fat, "weight": grams}}'
    try:
        response = requests.post(url, json={"contents": [{"parts": [{"text": prompt}]}]}, timeout=10)
        match = re.search(r'\{.*\}', response.json()['candidates'][0]['content']['parts'][0]['text'], re.DOTALL)
        return json.loads(match.group()) if match else {"cal": 250, "prot": 15, "carb": 10, "fat": 15, "weight": 200}
    except:
        return {"cal": 250, "prot": 15, "carb": 10, "fat": 15, "weight": 200}

# --- 1. التغذية والماء والتمارين ---
@app.post("/log_meal")
async def log_meal(user_id: str = Query(...), meal_type: str = Query(...), items_ar: str = Form(...)):
    meal_res = supabase.table("meals").insert({"user_id": user_id, "meal_type": meal_type}).execute()
    meal_id = meal_res.data[0]['id']
    nutri = get_ai_nutrition_estimate(items_ar)
    payload = {"meal_id": meal_id, "food_name": items_ar, "calories": float(nutri['cal']), "protein": float(nutri['prot']), "carbs": float(nutri['carb']), "fat": float(nutri['fat']), "weight_grams": float(nutri['weight'])}
    supabase.table("meal_items").insert(payload).execute()
    return {"status": "success", "data": payload}

@app.get("/get_daily_intake")
async def get_daily_intake(user_id: str = Query(...)):
    profile = supabase.table("profiles").select("*").eq("id", user_id).single().execute()
    targets = {"cal": profile.data.get("target_calories", 2000), "prot": 165.0, "fat": 55.0, "carb": 113.0}
    today = datetime.now().strftime("%Y-%m-%d")
    meals = supabase.table("meals").select("id").eq("user_id", user_id).gte("created_at", today).execute()
    meal_ids = [m['id'] for m in meals.data]
    items = supabase.table("meal_items").select("*").in_("meal_id", meal_ids).execute()
    totals = {"cal": sum(i['calories'] for i in items.data), "prot": sum(i['protein'] for i in items.data), "fat": sum(i['fat'] for i in items.data), "carb": sum(i['carbs'] for i in items.data)}
    return {"totals": totals, "targets": targets}

@app.post("/log_water")
async def log_water(user_id: str = Query(...), amount_ml: int = Query(...)):
    return supabase.table("water_logs").insert({"user_id": user_id, "amount_ml": amount_ml}).execute()

@app.post("/log_workout")
async def log_workout(user_id: str = Query(...), name: str = Form(...), mins: int = Form(...)):
    return supabase.table("workouts").insert({"user_id": user_id, "workout_name": name, "duration_min": mins}).execute()

# --- 2. المهام المجدولة (Scheduled Tasks) ---
@app.post("/add_task")
async def add_task(user_id: str = Query(...), task_name: str = Form(...)):
    """إضافة مهمة جديدة (مثلاً: جلسة يوجا)"""
    return supabase.table("tasks").insert({"user_id": user_id, "task_name": task_name, "is_completed": False}).execute()

@app.post("/complete_task")
async def complete_task(task_id: int = Query(...)):
    """تحديد المهمة كمكتملة"""
    return supabase.table("tasks").update({"is_completed": True}).eq("id", task_id).execute()

# --- 3. البروفايل والصور ---
@app.post("/upload_profile_pic")
async def upload_profile_pic(user_id: str = Query(...), file: UploadFile = File(...)):
    content = await file.read()
    path = f"profiles/{user_id}.jpg"
    supabase.storage.from_("avatars").upload(path, content, {"content-type": "image/jpeg"})
    url = supabase.storage.from_("avatars").get_public_url(path)
    supabase.table("profiles").update({"profile_pic_url": url}).eq("id", user_id).execute()
    return {"url": url}

# --- 4. النتيجة الإجمالية (Dashboard Score) ---
@app.get("/get_overall_score")
async def get_overall_score(user_id: str = Query(...)):
    today = datetime.now().strftime("%Y-%m-%d")
    # تغذية (40%) + ماء (20%) + تمارين (20%) + مهام (20%)
    intake = await get_daily_intake(user_id)
    score = min((intake['totals']['cal'] / intake['targets']['cal']) * 40, 40) if intake['targets']['cal'] > 0 else 0
    
    water_res = supabase.table("water_logs").select("amount_ml").eq("user_id", user_id).gte("created_at", today).execute()
    score += min((sum(w['amount_ml'] for w in water_res.data) / 2500) * 20, 20)
    
    work_res = supabase.table("workouts").select("duration_min").eq("user_id", user_id).gte("created_at", today).execute()
    score += min((sum(w['duration_min'] for w in work_res.data) / 45) * 20, 20)
    
    task_res = supabase.table("tasks").select("*").eq("user_id", user_id).gte("created_at", today).execute()
    if task_res.data:
        done = len([t for t in task_res.data if t['is_completed']])
        score += (done / len(task_res.data)) * 20

    return {"score": int(score), "display": f"{int(score)}/100"}