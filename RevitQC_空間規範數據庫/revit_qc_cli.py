#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Revit 空間規範數據庫與 QC 自動檢核命令行工具 (RevitQC CLI Tool)
"""

import os
import re
import csv
import json
import sys
import argparse
from typing import Dict, List, Any

class SpatialRuleDB:
    def __init__(self):
        self.rules: Dict[str, Dict[str, Any]] = {}

    def load_from_markdown(self, filepath: str):
        if not os.path.exists(filepath):
            print(f"❌ 找不到規範檔案: {filepath}")
            return

        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        # 按 H2 (## 空間名稱) 分割
        sections = re.split(r'\n(?=##\s+)', content)
        for sec in sections:
            lines = [l.strip() for l in sec.strip().split('\n') if l.strip()]
            if not lines:
                continue
            
            header_match = re.match(r'^##\s+(.+)$', lines[0])
            if not header_match:
                continue
            
            space_name = header_match.group(1).strip()
            rule = {
                "space_name": space_name,
                "doors": [],
                "wall_finish": "",
                "floor_finish": "",
                "ceiling_finish": "",
                "notes": "",
                "min_door_width": 0,
                "must_outward": False
            }

            for line in lines[1:]:
                if line.startswith('- **門窗編號**:'):
                    val = line.split(':', 1)[1].strip()
                    rule["doors"] = [d.strip() for d in val.split(',')]
                elif line.startswith('- **牆面粉刷編號**:'):
                    rule["wall_finish"] = line.split(':', 1)[1].strip()
                elif line.startswith('- **地面粉刷編號**:'):
                    rule["floor_finish"] = line.split(':', 1)[1].strip()
                elif line.startswith('- **天花粉刷編號**:'):
                    rule["ceiling_finish"] = line.split(':', 1)[1].strip()
                elif line.startswith('- **備註**:'):
                    rule["notes"] = line.split(':', 1)[1].strip()

            # 解析特殊規則 (如淨寬需求、外開需求)
            notes = rule["notes"]
            width_match = re.search(r'門寬淨寬需大於\s*(\d+)cm|淨寬需大於\s*(\d+)cm', notes)
            if width_match:
                w = width_match.group(1) or width_match.group(2)
                rule["min_door_width"] = int(w)
            
            if "外開門" in notes or "向避難方向" in notes:
                rule["must_outward"] = True

            self.rules[space_name] = rule

        print(f"✅ 成功載入 {len(self.rules)} 條空間規範規則自: {os.path.basename(filepath)}")

    def get_rule_for_space(self, space_name: str) -> Dict[str, Any]:
        if space_name in self.rules:
            return self.rules[space_name]
        matches = [rule for k, rule in self.rules.items() if k in space_name or space_name in k]
        if matches:
            matches.sort(key=lambda r: len(r["space_name"]), reverse=True)
            return matches[0]
        return None

class RevitQCInspector:
    def __init__(self, rule_db: SpatialRuleDB):
        self.rule_db = rule_db

    def inspect_csv(self, csv_filepath: str) -> List[Dict[str, Any]]:
        results = []
        if not os.path.exists(csv_filepath):
            print(f"❌ 找不到 CSV 檔案: {csv_filepath}")
            return results

        with open(csv_filepath, 'r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            for row in reader:
                room_id = row.get("房間編號", "").strip()
                room_name = row.get("房間名稱", "").strip()
                door = row.get("門窗編號", "").strip()
                wall = row.get("牆面粉刷編號", "").strip()
                floor = row.get("地面粉刷編號", "").strip()
                ceiling = row.get("天花粉刷編號", "").strip()
                width_str = row.get("門淨寬cm", "0").strip()
                swing = row.get("開門方向", "").strip()

                try:
                    width = float(width_str) if width_str else 0
                except ValueError:
                    width = 0

                # 智慧提取標註尺寸門寬 (如 90x210 中提取 90cm 門寬，門高 210 自動忽略不納入計算)
                m_dim = re.search(r'(\d+(?:\.\d+)?)\s*[xX*×]\s*\d+', door)
                if m_dim and width == 0:
                    width = float(m_dim.group(1))

                rule = self.rule_db.get_rule_for_space(room_name)
                
                issues = []
                status = "PASS"

                if not rule:
                    status = "WARNING"
                    issues.append(f"規範數據庫無「{room_name}」對應規範")
                else:
                    # 1. 檢查門窗編號
                    rule_doors = rule.get("doors", [])
                    if rule_doors and not any(d in door or door in d for d in rule_doors):
                        status = "FAIL"
                        issues.append(f"門窗編號不符合規範！實際: {door}，規範應為: {', '.join(rule_doors)}")

                    # 2. 檢查牆面粉刷
                    rule_wall = rule.get("wall_finish", "")
                    if rule_wall and rule_wall.split()[0] not in wall:
                        status = "FAIL"
                        issues.append(f"牆面粉刷不符！實際: {wall}，規範應為: {rule_wall}")

                    # 3. 檢查地面粉刷
                    rule_floor = rule.get("floor_finish", "")
                    if rule_floor and rule_floor.split()[0] not in floor:
                        status = "FAIL"
                        issues.append(f"地面粉刷不符！實際: {floor}，規範應為: {rule_floor}")

                    # 4. 檢查天花粉刷
                    rule_ceiling = rule.get("ceiling_finish", "")
                    if rule_ceiling and rule_ceiling.split()[0] not in ceiling:
                        status = "FAIL"
                        issues.append(f"天花粉刷不符！實際: {ceiling}，規範應為: {rule_ceiling}")

                    # 5. 門淨寬檢查
                    min_w = rule.get("min_door_width", 0)
                    if min_w > 0 and width < min_w:
                        status = "FAIL"
                        issues.append(f"門淨寬不足！實際: {width}cm < 規範要求: {min_w}cm")

                    # 6. 開門方向檢查
                    if rule.get("must_outward") and "外" not in swing:
                        status = "FAIL"
                        issues.append(f"開門方向違規！實際: {swing}，規範要求需為外開門/避難方向")

                results.append({
                    "room_id": room_id,
                    "room_name": room_name,
                    "door": door,
                    "wall": wall,
                    "floor": floor,
                    "ceiling": ceiling,
                    "width": width,
                    "swing": swing,
                    "status": status,
                    "issues": issues,
                    "matched_rule": rule["space_name"] if rule else "無"
                })

        return results

def print_summary(results: List[Dict[str, Any]]):
    total = len(results)
    passed = sum(1 for r in results if r["status"] == "PASS")
    warnings = sum(1 for r in results if r["status"] == "WARNING")
    failed = sum(1 for r in results if r["status"] == "FAIL")

    print("\n" + "="*60)
    print("📊 Revit 空間數據規範自動檢核結果報告")
    print("="*60)
    print(f"總房間數: {total} | ✅ 符合 (PASS): {passed} | ⚠️ 警告: {warnings} | ❌ 違規 (FAIL): {failed}")
    print(f"專案合規率: {passed / total * 100:.1f}%\n" if total > 0 else "")

    for r in results:
        badge = "✅ PASS" if r["status"] == "PASS" else ("⚠️ WARN" if r["status"] == "WARNING" else "❌ FAIL")
        print(f"[{badge}] 房間 {r['room_id']} - {r['room_name']} (門號: {r['door']})")
        if r["issues"]:
            for iss in r["issues"]:
                print(f"    └─ 🔴 {iss}")
        else:
            print("    └─ 所有粉刷編號、門窗規格與備註規範均符合。")
    print("="*60 + "\n")

def main():
    parser = argparse.ArgumentParser(description="Revit 空間規範數據庫 QC 檢核 CLI")
    parser.add_argument("--db", default="空間裝修與門窗對照表.md", help="Markdown 規範數據庫路徑")
    parser.add_argument("--csv", default="sample_revit_rooms.csv", help="Revit 房間數據 CSV 路徑")
    parser.add_argument("--out-json", help="匯出檢核結果 JSON 路徑")
    parser.add_argument("--out-html", help="匯出獨立 HTML 品質報告路徑")

    args = parser.parse_args()

    db = SpatialRuleDB()
    db.load_from_markdown(args.db)

    inspector = RevitQCInspector(db)
    results = inspector.inspect_csv(args.csv)

    print_summary(results)

    if args.out_json:
        with open(args.out_json, 'w', encoding='utf-8') as f:
            json.dump(results, f, ensure_ascii=False, indent=2)
        print(f"💾 檢核結果已儲存至 {args.out_json}")

    if args.out_html:
        generate_html_report(results, args.out_html)

def generate_html_report(results: List[Dict[str, Any]], out_path: str):
    total = len(results)
    passed = sum(1 for r in results if r["status"] == "PASS")
    failed = sum(1 for r in results if r["status"] == "FAIL")
    rate = (passed / total * 100) if total else 0

    rows_html = ""
    for r in results:
        badge = "badge-pass" if r["status"] == "PASS" else ("badge-warn" if r["status"] == "WARNING" else "badge-fail")
        issues_html = "".join([f"<li>🔴 {iss}</li>" for iss in r["issues"]]) if r["issues"] else "<span style='color:#10b981'>✅ 完全符合規範</span>"
        rows_html += f"""
        <tr>
            <td><b>{r['room_id']}</b></td>
            <td><b style="color:#06b6d4">{r['room_name']}</b></td>
            <td>{r['matched_rule']}</td>
            <td><code>{r['door']}</code></td>
            <td>{r['wall']}</td>
            <td>{r['floor']}</td>
            <td>{r['ceiling']}</td>
            <td><span class="badge {badge}">{r['status']}</span></td>
            <td><ul style="margin:0;padding-left:16px;color:#fca5a5">{issues_html}</ul></td>
        </tr>
        """

    html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>RevitQC 專案自動檢核報告</title>
    <style>
        body {{ font-family: sans-serif; background: #0f172a; color: #f8fafc; padding: 24px; }}
        h1 {{ color: #3b82f6; }}
        .stats {{ display: flex; gap: 20px; margin-bottom: 24px; }}
        .card {{ background: #1e293b; padding: 16px 24px; border-radius: 12px; border: 1px solid #334155; }}
        table {{ width: 100%; border-collapse: collapse; background: #1e293b; border-radius: 12px; overflow: hidden; }}
        th, td {{ padding: 12px 16px; border-bottom: 1px solid #334155; text-align: left; }}
        th {{ background: #0f172a; color: #94a3b8; }}
        .badge {{ padding: 4px 8px; border-radius: 12px; font-weight: bold; font-size: 12px; }}
        .badge-pass {{ background: rgba(16,185,129,0.2); color: #10b981; }}
        .badge-fail {{ background: rgba(239,68,68,0.2); color: #ef4444; }}
    </style>
</head>
<body>
    <h1>🏢 Revit 空間數據規範自動檢核報告</h1>
    <div class="stats">
        <div class="card"><h3>總房間數</h3><h2>{total}</h2></div>
        <div class="card"><h3 style="color:#10b981">符合 (PASS)</h3><h2>{passed}</h2></div>
        <div class="card"><h3 style="color:#ef4444">違規 (FAIL)</h3><h2>{failed}</h2></div>
        <div class="card"><h3 style="color:#06b6d4">合規率</h3><h2>{rate:.1f}%</h2></div>
    </div>
    <table>
        <thead>
            <tr><th>編號</th><th>名稱</th><th>對應規範</th><th>門號</th><th>牆面粉刷</th><th>地面粉刷</th><th>天花粉刷</th><th>狀態</th><th>異常說明</th></tr>
        </thead>
        <tbody>
            {rows_html}
        </tbody>
    </table>
</body>
</html>"""
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(html)
    print(f"📄 HTML 報告已成功匯出至 {out_path}")

if __name__ == "__main__":
    main()

