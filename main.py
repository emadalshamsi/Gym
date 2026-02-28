import os
import requests
import json
from fastapi import FastAPI, Form, Query
from supabase import create_client, Client
from deep_translator import GoogleTranslator
from dotenv import load_dotenv

load_dotenv()

app = FastAPI()

url: str = os.getenv("SUPABASE_URL")
key: str = os.getenv("SUPABASE_ANON_KEY")
ninjas_key: str = os.getenv("NINJAS_API_KEY")

supabase: Client = create_client(url, key)

def fetch_nutrition(food_name_en):
    api_url = f'https://api.api-ninjas.com/v1/nutrition?query={food_name_en}'
    response = requests.get(api_url, headers={'X-Api-Key': ninjas_key})
    return response.json()

@app.post("/log_meal")
async def log_meal(
    user_id: str = Query(...), 
    meal_type: str = Query(...), 
    items_ar: str = Form(...) 
):
    try:
        try:
            items_list = json.loads(items_ar.replace("'", '"'))
        except:
            items_list = [items_ar] if isinstance(items_ar, str) else items_ar

        meal_record = supabase.table("meals").insert({
            "user_id": user_id, 
            "meal_type": meal_type
        }).execute()
        
        meal_id = meal_record.data[0]['id']
        
        results = []
        for item_ar in items_list:
            item_en = GoogleTranslator(source='ar', target='en').translate(item_ar)
            data = fetch_nutrition(item_en)
            
            if data:
                nutrition = data[0]
                # تم تغيير المفتاح هنا من food_name_ar إلى food_name ليطابق سوبابيز
                item_data = {
                    "meal_id": meal_id,
                    "food_name": item_ar, 
                    "calories": nutrition['calories'],
                    "protein": nutrition['protein_g'],
                    "carbs": nutrition['carbohydrates_total_g'],
                    "fat": nutrition['fat_total_g']
                }
                supabase.table("meal_items").insert(item_data).execute()
                results.append(item_data)
                
        return {"status": "success", "message": "Meal logged successfully", "items": results}
    
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
    if gender == "male":
        bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5
    else:
        bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161
        
    multipliers = {"sedentary": 1.2, "light": 1.375, "moderate": 1.55, "active": 1.725}
    tdee = bmr * multipliers.get(activity, 1.2)
    
    if goal == "lose":
        target_calories = tdee - 500
    elif goal == "gain":
        target_calories = tdee + 500
    else:
        target_calories = tdee

    target_water = weight * 35 
    
    supabase.table("profiles").upsert({
        "id": user_id,
        "weight": weight,
        "height": height,
        "age": age,
        "gender": gender,
        "target_calories": int(target_calories),
        "target_water_ml": int(target_water)
    }).execute()
    
    return {"status": "success", "target_calories": int(target_calories), "target_water_ml": int(target_water)}