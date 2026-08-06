#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
門寬自動偵測與門高忽略邏輯測試腳本 (test_door_width.py)
"""

import re

TEST_DOOR_TEXTS = [
    "D-01 90x210",
    "SD1-A (120*240)",
    "D-05 W:95 H:210",
    "門寬 130cm 高 210cm",
    "90x210cm (內開門)",
    "FD1-A 120x240 (雙向開門)",
    "80x210",
    "D-02"  # 僅有門號無標註尺寸
]

def parse_door_width_only(text):
    """
    從 CAD/Revit 門號與尺寸文字中：
    1. 自動偵測「門寬 (Width)」
    2. 自動「忽略門高 (Height)」不納入比對計算
    """
    if not text:
        return 0
    
    # 模式 1: 90x210, 120*240, 95x210 (第一個數字即為門寬, 第二個數字門高忽略)
    m1 = re.search(r'(\d+(?:\.\d+)?)\s*[xX*×]\s*\d+', text)
    if m1:
        return float(m1.group(1))
    
    # 模式 2: W:95 或 門寬 130cm
    m2 = re.search(r'(?:W|門寬|淨寬|寬)[:=]?\s*(\d+(?:\.\d+)?)', text, re.IGNORECASE)
    if m2:
        return float(m2.group(1))

    # 模式 3: 單獨尺寸數字 (如 95cm 或 130)
    m3 = re.search(r'(\d+(?:\.\d+)?)\s*cm', text, re.IGNORECASE)
    if m3:
        return float(m3.group(1))

    return 0

def run_door_width_tests():
    print("==========================================================")
    print("🚪 平面門寬自動偵測 (門高高度不納入計算) 測試報告")
    print("==========================================================")
    
    for idx, raw in enumerate(TEST_DOOR_TEXTS, 1):
        w = parse_door_width_only(raw)
        if w > 0:
            print(f"[{idx:02d}] 原始門尺寸標註: \"{raw}\"")
            print(f"     └─ 🎯 成功偵測門寬: [{w:.1f} cm] (門高數據已自動忽略排除！)")
        else:
            print(f"[{idx:02d}] 原始門尺寸標註: \"{raw}\"")
            print(f"     └─ ℹ️ 僅含門編號，將依房間屬性表或淨寬欄位比對")
        print("----------------------------------------------------------")

if __name__ == "__main__":
    run_door_width_tests()
