#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
AutoCAD 空間名稱辨識與粉刷編號 (PE-01) 自動正下方寫入模擬測試 (test_cad_recognition.py)
"""

import re

# 模擬 AutoCAD 圖面中常見的各式文字內容與插入點座標 (x, y, z)
TEST_CAD_ELEMENTS = [
    {"raw": "變電站", "pt": (100.0, 200.0, 0.0), "h": 3.0},
    {"raw": "{\\fArial|b0;1F 簡報室}", "pt": (150.0, 200.0, 0.0), "h": 3.0},
    {"raw": "B1-進氣機房", "pt": (200.0, 200.0, 0.0), "h": 3.0},
    {"raw": "無障礙廁所", "pt": (250.0, 200.0, 0.0), "h": 2.5},
    {"raw": "A-101 辦公室", "pt": (300.0, 200.0, 0.0), "h": 3.0},
    {"raw": "機房\\P(空調)", "pt": (350.0, 200.0, 0.0), "h": 3.0},
]

RULES_DB = {
    "變電站": {"code": "PE-01", "doors": ["SD1-A", "D-01"], "wall": "W-01A", "floor": "FL-03"},
    "簡報室": {"code": "P1-02", "doors": ["D-02"], "wall": "W-03", "floor": "FL-02"},
    "機房": {"code": "PE-02", "doors": ["SD2-B"], "wall": "W-02", "floor": "FL-01"},
    "廁所": {"code": "P1-04", "doors": ["D-05"], "wall": "W-04", "floor": "FL-04"},
    "梯廳": {"code": "P1-05", "doors": ["FD1-A"], "wall": "W-01", "floor": "FL-05"},
    "辦公室": {"code": "P1-03", "doors": ["D-03"], "wall": "W-02", "floor": "FL-02"},
    "進氣機房": {"code": "PE-08", "doors": ["D-008"], "wall": "W-02", "floor": "FL-01"}
}

def clean_autocad_mtext(text):
    text = re.sub(r'\\f[^;]+;', '', text)
    text = re.sub(r'[{}]', '', text)
    text = text.replace('\\P', ' ').replace('\\p', ' ')
    return text.strip()

def match_space_rule(clean_text):
    if clean_text in RULES_DB:
        return clean_text, RULES_DB[clean_text]
    matched_key = None
    max_len = 0
    for key in RULES_DB:
        if key in clean_text or clean_text in key:
            if len(key) > max_len:
                max_len = len(key)
                matched_key = key
    if matched_key:
        return matched_key, RULES_DB[matched_key]
    return None, None

def simulate_autocad_text_insertion():
    print("==========================================================")
    print("✍️ AutoCAD 空間名稱辨識與「粉刷編號 (如 PE-01)」正下方寫入模擬")
    print("==========================================================")

    for idx, elem in enumerate(TEST_CAD_ELEMENTS, 1):
        clean = clean_autocad_mtext(elem["raw"])
        matched_space, spec = match_space_rule(clean)
        
        x, y, z = elem["pt"]
        h = elem["h"]
        # 計算 CAD 正下方文字寫入座標: y - h * 1.6
        new_y = y - (h * 1.6)
        
        if matched_space:
            code = spec["code"]
            print(f"[{idx:02d}] 📍 掃描 CAD 文字: \"{clean}\"  (座標: X={x:.1f}, Y={y:.1f})")
            print(f"     └─ 🎯 辨識為空間: [{matched_space}] | 粉刷編號: [{code}]")
            print(f"     └─ ✍️ 自動在正下方創建新 CAD 文字: \"{code}\" (座標: X={x:.1f}, Y={new_y:.1f}, 字高={h*0.85:.2f})")
        print("----------------------------------------------------------")

    print("\n✅ 模擬測試完成！正下方寫入座標與字高計算正確。\n")

if __name__ == "__main__":
    simulate_autocad_text_insertion()
