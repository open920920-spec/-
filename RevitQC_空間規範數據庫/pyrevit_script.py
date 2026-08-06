# -*- coding: utf-8 -*-
"""
RevitQC pyRevit 工具面板腳本 (pyRevit Ribbon PushButton Extension)
讓 BIM 工程師在 Revit 工具列按鈕一鍵執行「空間規範數據庫 QC 自動對照與寫入」
"""

from pyrevit import script, forms
from pyrevit.revit import doc, DB
import json
import os
import re

# 1. 取得與現有空間規範數據庫的連動檔案路徑
script_dir = os.path.dirname(__file__)
md_path = os.path.join(script_dir, "空間裝修與門窗對照表.md")

if not os.path.exists(md_path):
    md_path = forms.pick_file(file_ext='md', title='選擇建築空間規範數據庫 (.md)')

if not md_path:
    forms.alert("未選擇規範檔案，操作取消。", exitscript=True)

# 2. 解析 Markdown 規範檔內容
def parse_markdown_db(filepath):
    rules = {}
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    sections = content.split('\n## ')
    for sec in sections[1:]:
        lines = sec.strip().split('\n')
        space_name = lines[0].strip()
        rule = {
            "finish_code": "",
            "doors": [],
            "lock_hardware": "",
            "wall": "",
            "floor": "",
            "ceiling": "",
            "notes": "",
            "min_w": 0,
            "outward": False
        }
        for l in lines[1:]:
            l = l.strip()
            if "- **粉刷對照編號**:" in l:
                rule["finish_code"] = l.split(":", 1)[1].strip()
            elif "- **門窗編號**:" in l:
                rule["doors"] = [d.strip() for d in l.split(":", 1)[1].split(",")]
            elif "- **門鎖五金編號**:" in l or "- **門鎖五金**:" in l:
                rule["lock_hardware"] = l.split(":", 1)[1].strip()
            elif "- **牆面粉刷編號**:" in l:
                rule["wall"] = l.split(":", 1)[1].strip()
            elif "- **地面粉刷編號**:" in l:
                rule["floor"] = l.split(":", 1)[1].strip()
            elif "- **天花粉刷編號**:" in l:
                rule["ceiling"] = l.split(":", 1)[1].strip()
            elif "- **備註**:" in l:
                rule["notes"] = l.split(":", 1)[1].strip()

        if "門寬淨寬需大於" in rule["notes"] or "淨寬需大於" in rule["notes"]:
            m = re.search(r'淨寬需大於\s*(\d+)cm', rule["notes"])
            if m: rule["min_w"] = int(m.group(1))

        if "外開門" in rule["notes"] or "向避難方向" in rule["notes"]:
            rule["outward"] = True

        rules[space_name] = rule
    return rules

rules_db = parse_markdown_db(md_path)

# 3. 抓取 Revit 模型中所有房間 Elements
rooms = DB.FilteredElementCollector(doc).OfCategory(DB.BuiltInCategory.OST_Rooms).ToElements()

output = script.get_output()
output.print_md("# 🏢 RevitQC 空間規範數據庫 - 即時檢核報告")
output.print_md("正在讀取規範檔案：`{}`".format(md_path))
output.print_md("---")

pass_count = 0
fail_count = 0

with DB.Transaction(doc, "RevitQC 空間自動檢核"):
    for room in rooms:
        r_name = room.LookupParameter("名稱").AsString() if room.LookupParameter("名稱") else ""
        if not r_name:
            continue

        # 精準與最長匹配
        matched_keys = [k for k in rules_db.keys() if k in r_name or r_name in k]
        if not matched_keys:
            output.print_md("⚠️ **[WARN]** 房間 `{}` ({})：規範數據庫無對應項目".format(room.Number, r_name))
            continue

        matched_keys.sort(key=lambda k: len(k), reverse=True)
        matched_key = matched_keys[0]
        rule = rules_db[matched_key]
        issues = []

        # 讀取參數
        w_val = room.LookupParameter("牆面粉刷").AsString() if room.LookupParameter("牆面粉刷") else ""
        f_val = room.LookupParameter("地面粉刷").AsString() if room.LookupParameter("地面粉刷") else ""
        c_val = room.LookupParameter("天花板粉刷").AsString() if room.LookupParameter("天花板粉刷") else ""
        d_val = room.LookupParameter("門標註").AsString() if room.LookupParameter("門標註") else (room.LookupParameter("門窗編號").AsString() if room.LookupParameter("門窗編號") else "")

        # 比對規則
        if rule["wall"] and w_val and not rule["wall"].startswith(w_val.split(' ')[0]):
            issues.append("牆面粉刷不符 (實際: {}, 規範: {})".format(w_val, rule["wall"]))
        if rule["floor"] and f_val and not rule["floor"].startswith(f_val.split(' ')[0]):
            issues.append("地面粉刷不符 (實際: {}, 規範: {})".format(f_val, rule["floor"]))
        if rule["ceiling"] and c_val and not rule["ceiling"].startswith(c_val.split(' ')[0]):
            issues.append("天花粉刷不符 (實際: {}, 規範: {})".format(c_val, rule["ceiling"]))

        # 門寬解析 (如 90x210 取 90cm, 門高自動忽略)
        door_w = 0
        if d_val:
            m_dim = re.search(r'(\d+(?:\.\d+)?)\s*[xX*×]\s*\d+', d_val)
            if m_dim:
                door_w = float(m_dim.group(1))

        if rule["min_w"] > 0 and door_w > 0 and door_w < rule["min_w"]:
            issues.append("門淨寬不足 (實際: {}cm, 規範: {}cm)".format(door_w, rule["min_w"]))

        # 寫入專案檢核 Shared Parameters (若存在)
        p_status = room.LookupParameter("QC_Status")
        p_issues = room.LookupParameter("QC_Issues")
        p_finish_code = room.LookupParameter("Target_FinishCode")
        p_lock = room.LookupParameter("Target_LockHardware")

        if p_finish_code and not p_finish_code.IsReadOnly and rule["finish_code"]:
            p_finish_code.Set(rule["finish_code"])
        if p_lock and not p_lock.IsReadOnly and rule["lock_hardware"]:
            p_lock.Set(rule["lock_hardware"])

        if issues:
            fail_count += 1
            if p_status and not p_status.IsReadOnly: p_status.Set("FAIL")
            if p_issues and not p_issues.IsReadOnly: p_issues.Set("; ".join(issues))
            
            output.print_md("❌ **[FAIL]** 房間 `{}` - `{}` (粉刷編號: `{}`)：".format(room.Number, r_name, rule["finish_code"] or "N/A"))
            for iss in issues:
                output.print_md("&nbsp;&nbsp;&nbsp;&nbsp;🔴 " + iss)
        else:
            pass_count += 1
            if p_status and not p_status.IsReadOnly: p_status.Set("PASS")
            if p_issues and not p_issues.IsReadOnly: p_issues.Set("符合規範")
            output.print_md("✅ **[PASS]** 房間 `{}` - `{}` (粉刷編號: `{}`)：完全符合規範".format(room.Number, r_name, rule["finish_code"] or "N/A"))

output.print_md("---")
output.print_md("### 📊 檢核結果總計：符合 **{}** 房間 | 違規 **{}** 房間".format(pass_count, fail_count))
forms.alert("RevitQC 空間對照與檢核完成！\n符合: {} | 違規: {}".format(pass_count, fail_count))
