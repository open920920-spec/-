#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RevitQC Spatial Suite - 全系統端到端完整測試與排查腳本
"""

import os
import json
import subprocess
import sys

def test_cli():
    print("1. 🧪 測試 Python CLI 與 QC 檢核引擎 (revit_qc_cli.py)...")
    res = subprocess.run(
        ["python3", "revit_qc_cli.py", "--db", "空間裝修與門窗對照表.md", "--csv", "sample_revit_rooms.csv", "--out-json", "result.json", "--out-html", "report.html"],
        capture_output=True, text=True
    )
    if res.returncode != 0:
        print(f"❌ CLI 執行失敗: {res.stderr}")
        return False
    print("   ✅ CLI 檢核完成！成功產生 result.json 與 report.html")
    return True

def test_lisp():
    print("2. 🧪 測試 AutoCAD LISP 語法與規則結構 (cad_qc.lsp)...")
    res = subprocess.run(["python3", "test_lsp.py"], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"❌ LISP 語法校驗失敗: {res.stderr}")
        return False
    print("   ✅ LISP 語法與括號對稱性檢查 100% 通過！")
    return True

def test_cad_recognition():
    print("3. 🧪 測試 AutoCAD MTEXT 淨化與正下方寫入 (test_cad_recognition.py)...")
    res = subprocess.run(["python3", "test_cad_recognition.py"], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"❌ CAD 辨識測試失敗: {res.stderr}")
        return False
    print("   ✅ CAD 空間名稱辨識與粉刷編號 (PE-01) 正下方寫入模擬測試 100% 通過！")
    return True

def test_json_output():
    print("4. 🧪 檢視 QC 異常數據精準度 (result.json)...")
    with open("result.json", "r", encoding="utf-8") as f:
        data = json.load(f)
    
    total = len(data)
    passed = sum(1 for r in data if r["status"] == "PASS")
    failed = sum(1 for r in data if r["status"] == "FAIL")

    print(f"   📊 總檢核: {total} 個房間 | 通過: {passed} | 違規標示: {failed}")
    
    # 驗證故意設定的 3 個違規案例是否精準抓出
    fail_room_ids = [r["room_id"] for r in data if r["status"] == "FAIL"]
    expected_fails = ["102", "105", "202"]
    
    if set(fail_room_ids) == set(expected_fails):
        print(f"   🎯 違規房間標記完美精準！已精準抓出所有違規房間: {fail_room_ids}")
        return True
    else:
        print(f"   ⚠️ 違規標記不符，實際: {fail_room_ids}，預期: {expected_fails}")
        return False

def main():
    print("==========================================================")
    print("🏢 RevitQC Spatial Suite 全系統自動化排查與測試套件")
    print("==========================================================")
    
    c1 = test_cli()
    c2 = test_lisp()
    c3 = test_cad_recognition()
    c4 = test_json_output()

    print("==========================================================")
    if c1 and c2 and c3 and c4:
        print("🎉 全系統排查完成！所有 4 項核心模組測試 100% 成功無誤！")
    else:
        print("❌ 排查發現異常，請查看上述報告。")
        sys.exit(1)

if __name__ == "__main__":
    main()
