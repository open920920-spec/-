#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
全專案資安與敏感資訊掃描腳本 (verify_security.py)
"""

import os
import re

def scan_security(workspace):
    print("==========================================================")
    print("🔒 RevitQC 專案資安與敏感資訊 (Security Audit) 深度掃描")
    print("==========================================================")

    patterns = [
        (r'sk-[a-zA-Z0-9]{20,}', "OpenAI/API Key"),
        (r'ghp_[a-zA-Z0-9]{36}', "GitHub Personal Access Token"),
        (r'AKIA[0-9A-Z]{16}', "AWS Access Key"),
        (r'AIza[0-9A-Za-z-_]{35}', "Google API Key"),
        (r'-----BEGIN\s+PRIVATE\s+KEY-----', "RSA/PEM Private Key"),
    ]

    found_count = 0
    for root, dirs, files in os.walk(workspace):
        if '.git' in root or '__pycache__' in root:
            continue
        for file in files:
            filepath = os.path.join(root, file)
            try:
                with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    for pattern, label in patterns:
                        matches = re.findall(pattern, content)
                        if matches:
                            print(f"⚠️ 發現 {label}: 檔案 {file}")
                            found_count += 1
            except Exception:
                pass

    if found_count == 0:
        print("✅ 全專案資安掃描 100% 通過！未發現任何硬編碼 API Key、私鑰或 Token。")
    return found_count == 0

if __name__ == "__main__":
    scan_security("/Users/yezhenxi/Desktop/RevitQC_空間規範數據庫")
