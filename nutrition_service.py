from deep_translator import GoogleTranslator
import requests

def get_nutrition_data(food_name_ar):
    # 1. الترجمة من العربي للانجليزي
    translated = GoogleTranslator(source='ar', target='en').translate(food_name_ar)
    
    # 2. طلب البيانات من API Ninjas (سنحتاج مفتاحهم لاحقاً)
    api_url = f'https://api.api-ninjas.com/v1/nutrition?query={translated}'
    # ملاحظة: سنحتاج لـ API Key من موقعهم، سأخبرك كيف تجلبه مجاناً
    
    return {"original": food_name_ar, "english": translated}
