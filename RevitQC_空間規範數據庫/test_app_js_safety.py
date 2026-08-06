#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
app.js DOM 事件監聽器與 DOM 元素存取安全性檢查腳本 (test_app_js_safety.py)
"""

import re

def check_app_js_safety(filepath):
    print("==========================================================")
    print("🔬 app.js JavaScript DOM 存取安全性與事件綁定排查")
    print("==========================================================")
    
    with open(filepath, 'r', encoding='utf-8') as f:
        code = f.read()

    # 搜尋所有 getElementById / querySelector 及其隨後的 addEventListener
    lines = code.split('\n')
    issues = []
    
    for idx, line in enumerate(lines, 1):
        if 'addEventListener' in line:
            # 檢查前一行或當前行是否有 null check
            context = "\n".join(lines[max(0, idx-5):idx])
            if 'getElementById' in context and 'if (' not in context and '?' not in line:
                # 可能存在空指標風險
                issues.append((idx, line.strip()))

    print(f"📄 分析檔案: {filepath} (總行數: {len(lines)})")
    if issues:
        print(f"⚠️ 發現 {len(issues)} 處潛在無保護的 addEventListener 調用:")
        for line_num, line_code in issues:
            print(f"   Line {line_num:04d}: {line_code}")
    else:
        print("✅ 所有事件監聽器皆具備安全的 null 防護檢查！")

if __name__ == "__main__":
    check_app_js_safety("app.js")
