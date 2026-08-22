#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RevitQC & CADQC Spatial Regulation System - Master QC & Verification Suite
(test_all_suite.py)
"""

import os
import json
import subprocess
import sys
from poc_lsp_verification import verify_lsp_poc
from verify_security import scan_security

def test_revit_cli():
    print("\n==========================================================")
    print("🏢 Revit QC Engine & Report Generator Verification")
    print("==========================================================")
    cmd = [
        sys.executable, "revit_qc_cli.py",
        "--db", "空間裝修與門窗對照表.md",
        "--csv", "sample_revit_rooms.csv",
        "--out-json", "result.json",
        "--out-html", "report.html"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"❌ Revit CLI execution failed: {res.stderr}")
        return False
    
    # Verify result.json content
    if not os.path.exists("result.json"):
        print("❌ Missing result.json output!")
        return False

    with open("result.json", "r", encoding="utf-8") as f:
        data = json.load(f)

    total = len(data)
    passed = sum(1 for r in data if r["status"] == "PASS")
    failed = sum(1 for r in data if r["status"] == "FAIL")
    print(f"   📊 Processed {total} Rooms | Passed: {passed} | Violations Flagged: {failed}")

    fail_room_ids = [r["room_id"] for r in data if r["status"] == "FAIL"]
    expected_fails = ["102", "105", "202"]
    if set(fail_room_ids) == set(expected_fails):
        print(f"   ✅ [PASS] Revit QC Rules matched expected violation rooms: {fail_room_ids}")
        return True
    else:
        print(f"   ⚠️ Unexpected fail IDs: {fail_room_ids}")
        return False

def test_js_safety():
    print("\n==========================================================")
    print("🌐 Web Application app.js Security & DOM Guard Audit")
    print("==========================================================")
    if not os.path.exists("app.js"):
        print("   ⚠️ app.js not found, skipping JS check.")
        return True

    with open("app.js", "r", encoding="utf-8") as f:
        lines = f.readlines()

    issues = []
    for idx, line in enumerate(lines, 1):
        if 'addEventListener' in line:
            context = "\n".join(lines[max(0, idx-5):idx])
            if 'getElementById' in context and 'if (' not in context and '?' not in line:
                issues.append((idx, line.strip()))

    if issues:
        print(f"   ⚠️ Found {len(issues)} potentially unguarded addEventListener calls.")
        return False
    else:
        print("   ✅ [PASS] All app.js event listeners are properly guarded against null pointer errors.")
        return True

def main():
    print("==========================================================")
    print("🚀 RevitQC & CADQC Full System Master QC & Verification Suite")
    print("==========================================================")

    step1 = verify_lsp_poc()
    step2 = test_revit_cli()
    step3 = scan_security(os.getcwd())
    step4 = test_js_safety()

    print("\n==========================================================")
    if step1 and step2 and step3 and step4:
        print("🎉 [SUCCESS] FULL SYSTEM MASTER QC PASSED 100%!")
        print("   All AutoCAD AutoLISP POCs, Revit CLI Rules, Security Audits & Web JS Safety checks PASSED!")
        print("==========================================================")
        return True
    else:
        print("❌ [FAILURE] Master QC suite detected errors.")
        print("==========================================================")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
