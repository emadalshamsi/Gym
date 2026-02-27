import os
from supabase import create_client, Client
from fastapi import FastAPI

# إعداد الربط مع Supabase
url: str = "https://evmqfqsiuzdcrxwoioau.supabase.co"
key: str = "sb_publishable_m5q3vZQMwZgCupn8c62Iug_sWpXe3-N"
supabase: Client = create_client(url, key)

app = FastAPI()

@app.get("/")
def home():
    return {"message": "Welcome to your Health App Backend!"}

# دالة حفظ بيانات الاستبيان
@app.post("/save_profile")
def save_profile(user_id: str, data: dict):
    # هنا سنستخدم معادلة Mifflin-St Jeor التي شرحتها لك سابقاً
    # لحساب الأهداف ثم حفظها في جدول profiles
    response = supabase.table("profiles").insert({
        "id": user_id,
        "full_name": data.get("name"),
        "weight": data.get("weight"),
        "height": data.get("height"),
        "age": data.get("age"),
        "gender": data.get("gender"),
        "target_calories": data.get("calculated_calories"),
        "target_water_ml": data.get("calculated_water")
    }).execute()
    return response
