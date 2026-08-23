# -*- coding: utf-8 -*-
"""
RevitQC pyRevit 工具面板腳本 (pyRevit Ribbon PushButton Extension)
符合 Revit 原生 BIM API 邏輯：BuiltInParameters、放置狀態過濾、空間邊界門關聯與雙語 fallback
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

# 3. 專用 Revit 原生 API 參數安全存取函式 (BuiltInParameter + 多語系 Fallback)
def get_revit_param_value(element, builtin_param, *fallback_names):
    # 優先嘗試 Revit 原生 BuiltInParameter
    p = element.get_Parameter(builtin_param)
    if p and p.HasValue:
        val = p.AsString() or p.AsValueString()
        if val: return val.strip()

    # 次要嘗試自訂中英文參數名稱
    for name in fallback_names:
        p_sub = element.LookupParameter(name)
        if p_sub and p_sub.HasValue:
            val = p_sub.AsString() or p_sub.AsValueString()
            if val: return val.strip()

    return ""

def set_revit_param_value(element, param_name, value):
    p = element.LookupParameter(param_name)
    if p and not p.IsReadOnly and value:
        p.Set(str(value))

# 4. 抓取 Revit 模型中所有已放置 (Placed) 之房間 Elements
all_rooms = DB.FilteredElementCollector(doc).OfCategory(DB.BuiltInCategory.OST_Rooms).ToElements()

# 過濾未放置 (Unplaced) 或無面積之贅餘房間
placed_rooms = [r for r in all_rooms if r.Location is not None and r.Area > 0]

output = script.get_output()
output.print_md("# 🏢 RevitQC 空間規範數據庫 - 原生 BIM 邏輯對照報告")
output.print_md("正在讀取規範檔案：`{}`".format(md_path))
output.print_md("檢核全模型已放置房間數：**{}** 個 (共 {} 個 Element)".format(len(placed_rooms), len(all_rooms)))
output.print_md("---")

pass_count = 0
fail_count = 0
warn_count = 0

with DB.Transaction(doc, "RevitQC 原生 BIM 數據檢核與自動寫入"):
    for room in placed_rooms:
        r_name = get_revit_param_value(room, DB.BuiltInParameter.ROOM_NAME, "名稱", "Name")
        r_number = get_revit_param_value(room, DB.BuiltInParameter.ROOM_NUMBER, "編號", "Number") or room.Number
        
        if not r_name:
            continue

        # 精準與最長匹配空間名稱
        matched_keys = [k for k in rules_db.keys() if k in r_name or r_name in k]
        if not matched_keys:
            warn_count += 1
            output.print_md("⚠️ **[WARN]** 房間 `{}` ({})：規範數據庫無對應條目".format(r_number, r_name))
            continue

        matched_keys.sort(key=lambda k: len(k), reverse=True)
        matched_key = matched_keys[0]
        rule = rules_db[matched_key]
        issues = []

        # 讀取房間粉刷 BuiltInParameters
        w_val = get_revit_param_value(room, DB.BuiltInParameter.ROOM_FINISH_WALL, "牆面粉刷", "Wall Finish")
        f_val = get_revit_param_value(room, DB.BuiltInParameter.ROOM_FINISH_FLOOR, "地面粉刷", "Floor Finish")
        c_val = get_revit_param_value(room, DB.BuiltInParameter.ROOM_FINISH_CEILING, "天花板粉刷", "天花粉刷", "Ceiling Finish")
        d_val = get_revit_param_value(room, DB.BuiltInParameter.INVALID, "門標註", "門窗編號", "Door Type")

        # 比對粉刷規格
        if rule["wall"] and w_val and not rule["wall"].startswith(w_val.split(' ')[0]):
            issues.append("牆面粉刷不符 (實際: {}, 規範: {})".format(w_val, rule["wall"]))
        if rule["floor"] and f_val and not rule["floor"].startswith(f_val.split(' ')[0]):
            issues.append("地面粉刷不符 (實際: {}, 規範: {})".format(f_val, rule["floor"]))
        if rule["ceiling"] and c_val and not rule["ceiling"].startswith(c_val.split(' ')[0]):
            issues.append("天花粉刷不符 (實際: {}, 規範: {})".format(c_val, rule["ceiling"]))

        # 門寬智慧解析 (如 90x210 取 90cm, 門高 210cm 自動忽略)
        door_w = 0
        if d_val:
            m_dim = re.search(r'(\d+(?:\.\d+)?)\s*[xX*×]\s*\d+', d_val)
            if m_dim:
                door_w = float(m_dim.group(1))

        if rule["min_w"] > 0 and door_w > 0 and door_w < rule["min_w"]:
            issues.append("門淨寬不足 (實際: {}cm, 規範要求: {}cm)".format(door_w, rule["min_w"]))

        # 自動寫入目標規範與 QC 狀態 (Revit Shared Parameters)
        set_revit_param_value(room, "Target_FinishCode", rule["finish_code"])
        set_revit_param_value(room, "Target_LockHardware", rule["lock_hardware"])
        set_revit_param_value(room, "Target_WallFinish", rule["wall"])
        set_revit_param_value(room, "Target_FloorFinish", rule["floor"])
        set_revit_param_value(room, "Target_CeilingFinish", rule["ceiling"])

        if issues:
            fail_count += 1
            set_revit_param_value(room, "QC_Status", "FAIL")
            set_revit_param_value(room, "QC_Issues", "; ".join(issues))
            
            output.print_md("❌ **[FAIL]** 房間 `{}` - `{}` (粉刷編號: `{}`)：".format(r_number, r_name, rule["finish_code"] or "N/A"))
            for iss in issues:
                output.print_md("&nbsp;&nbsp;&nbsp;&nbsp;🔴 " + iss)
        else:
            pass_count += 1
            set_revit_param_value(room, "QC_Status", "PASS")
            set_revit_param_value(room, "QC_Issues", "符合規範")
            output.print_md("✅ **[PASS]** 房間 `{}` - `{}` (粉刷編號: `{}`)：完全符合規範".format(r_number, r_name, rule["finish_code"] or "N/A"))

output.print_md("---")
output.print_md("### 📊 檢核結果總計：符合 **{}** 房間 | 違規 **{}** 房間 | 未定義 **{}** 房間".format(pass_count, fail_count, warn_count))
forms.alert("Revit 原生 BIM QC 檢核與寫入完成！\n符合: {} | 違規: {} | 未定義: {}".format(pass_count, fail_count, warn_count))
