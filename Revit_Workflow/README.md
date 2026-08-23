# 🏢 RevitQC 建築空間規範與檢核系統 - Revit 外掛操作流程指南

本資料夾包含了 **Revit BIM 模型** 執行空間裝修、門窗與門鎖五金規範對照與自動寫入的全套工具與操作手冊。

---

## 📂 資料夾檔案說明

- 📄 **`README.md`**：Revit 操作流詳細說明文件（本檔）。
- 🐍 **`pyrevit_script.py`**：pyRevit 工具面板專用腳本（可直接放在 pyRevit 按鈕資料夾下）。
- 📝 **`RevitQC_SharedParameters.txt`**：Revit 標準共用參數定義檔。
- 📊 **`sample_revit_rooms.csv`**：測試用 Revit 房間匯出範例資料檔。

---

## 🚀 完整操作流程步驟

### 步驟 1：匯入 Revit 共用參數 (Shared Parameters)
1. 開啟 Revit，進入頂部功能區 **「管理」 (Manage)** 頁籤。
2. 點擊 **「共用參數」 (Shared Parameters)** 按鈕。
3. 點擊「瀏覽」，選取本資料夾下的 **`RevitQC_SharedParameters.txt`**。
4. 進入 **「專案參數」 (Project Parameters)**，將以下參數新增至 **「房間」 (Rooms)** 類別：
   - `QC_Status` (文字)：檢核合規狀態 (`PASS` / `FAIL`)
   - `QC_Issues` (文字)：檢核違規說明
   - `Target_FinishCode` (文字)：目標粉刷對照編號 (`PE-01` ~ `PE-08`)
   - `Target_LockHardware` (文字)：目標門鎖五金編號 (`HD-01` ~ `HD-06`)

---

### 步驟 2：安裝與執行 pyRevit 按鈕外掛
1. 安裝 [pyRevit](https://github.com/eirannejad/pyRevit) 擴充工具。
2. 將 **`pyrevit_script.py`** 放入 pyRevit 擴充功能目錄（例如 `RevitQC.extension/RevitQC.tab/QC.panel/Check.pushbutton/script.py`）。
3. 重新載入 pyRevit，Revit 頂部工具列將出現 **「空間規範檢核」** 按鈕。
4. 點擊按鈕，系統將自動讀取 `空間裝修與門窗對照表.md`，並執行 100% 原生 BIM 邏輯檢核與參數自動寫入！

---

### 步驟 3：使用 Dynamo Python 腳本（備選方式）
若專案未安裝 pyRevit：
1. 開啟 **Dynamo**，新建一個 Python Script 節點。
2. 開啟 Web 系統 (`index.html`) 的 **「Revit Dynamo 腳本」** 頁籤，點擊「一鍵複製程式碼」。
3. 貼入 Dynamo Python 節點並執行，即可完成同等效果之全模型房間規範檢核與寫入。

---

### 步驟 4：匯出 CSV 並於 Web / Excel 產出正式報告
1. 將 Revit 房間明細表匯出為 `CSV` 檔案。
2. 開啟 Web 系統，將 CSV 拖曳至 **「Revit 數據 QC 檢核器」**。
3. 點擊 **「匯出 Excel 報告 (.xlsx)」**，即可獲得帶有時間戳記、永不覆寫的正式專案品質檢核報告！
