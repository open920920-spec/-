/* ==========================================================================
   空間檢核門窗粉刷管理系統 - Application Logic Engine (app.js)
   ========================================================================== */

// --- Default Initial Markdown Database Content ---
const DEFAULT_MD_CONTENT = `# 🏢 建築空間裝修與門窗標準規範數據庫

本資料夾（空間規範數據庫）存放所有空間名稱與門窗編號、粉刷編號、門鎖五金編號之連動對照表。外掛與 QC 工具執行時將自動讀取本資料夾下所有 .md 檔。

---

## 變電站
- **粉刷對照編號**: PE-01
- **門窗編號**: SD1-A, D-01
- **門鎖五金編號**: HD-01 (電子感應鎖 + 雙匙甲種防火鎖)
- **牆面粉刷編號**: W-01A (防潮防鏽漆)
- **地面粉刷編號**: FL-03 (高強度耐磨環氧 resin)
- **天花粉刷編號**: CL-02 (防潮矽酸鈣板)
- **備註**: 避難通口需設甲種防火門，門寬淨寬需大於 120cm

## 簡報室
- **粉刷對照編號**: P1-02
- **門窗編號**: D-02, D-02A
- **門鎖五金編號**: HD-02 (水平把手通道鎖 + 靜音門鎖組)
- **牆面粉刷編號**: W-03 (吸音裝修板)
- **地面粉刷編號**: FL-02 (高密度方塊地毯)
- **天花粉刷編號**: CL-01 (明架礦纖天花板)
- **備註**: 需檢核採光面積小於 1/8 處之防音規格

## 機房
- **粉刷對照編號**: PE-02
- **門窗編號**: SD2-B
- **門鎖五金編號**: HD-03 (避難壓棒鎖 Panic Bar + 自動關門器)
- **牆面粉刷編號**: W-02 (水性乳膠漆)
- **地面粉刷編號**: FL-01 (水泥粉光防塵漆)
- **天花粉刷編號**: CL-01 (明架矽酸鈣板)
- **備註**: 門需開向避難方向 (外開門)

## 廁所
- **粉刷對照編號**: P1-04
- **門窗編號**: D-05
- **門鎖五金編號**: HD-04 (無障礙顯示鎖 + 大型轉手鎖組)
- **牆面粉刷編號**: W-04 (貼 30x60cm 石質壁磚)
- **地面粉刷編號**: FL-04 (貼 30x30cm 防滑地磚)
- **天花粉刷編號**: CL-03 (PVC 防潮天花板)
- **備註**: 無障礙廁所迴轉直徑須滿 150cm，門淨寬需大於 90cm

## 梯廳
- **粉刷對照編號**: P1-05
- **門窗編號**: FD1-A
- **門鎖五金編號**: HD-05 (常開啟電磁順序鎖 + 防火門五金)
- **牆面粉刷編號**: W-01 (耐燃一級水性漆)
- **地面粉刷編號**: FL-05 (拋光石英磚)
- **天花粉刷編號**: CL-01 (暗架石膏板)
- **備註**: 逃生管道與安全梯前室需符合 1 小時防火時效

## 辦公室
- **粉刷對照編號**: P1-03
- **門窗編號**: D-03
- **門鎖五金編號**: HD-02 (水平把手鎖 + 門檔)
- **牆面粉刷編號**: W-02 (水性乳膠漆)
- **地面粉刷編號**: FL-02 (高密度方塊地毯)
- **天花粉刷編號**: CL-01 (明架礦纖天花板)
- **備註**: 門寬淨寬需大於 90cm，採光通風面積需符合建築技術規則

## 儲藏室
- **粉刷對照編號**: P1-06
- **門窗編號**: D-04
- **門鎖五金編號**: HD-06 (單匙鎖 + 防塵門檻條)
- **牆面粉刷編號**: W-02 (水性乳膠漆)
- **地面粉刷編號**: FL-01 (水泥粉光防塵漆)
- **天花粉刷編號**: CL-02 (防潮矽酸鈣板)
- **備註**: 設自動煙感探測與門檻防塵條

## 進氣機房
- **粉刷對照編號**: PE-08
- **門窗編號**: D-008
- **門鎖五金編號**: HD-03 (防爆安全門鎖 + 自動關門器)
- **牆面粉刷編號**: W-02 (水性乳膠漆)
- **地面粉刷編號**: FL-01 (水泥粉光防塵漆)
- **天花粉刷編號**: CL-02 (防潮矽酸鈣板)
- **備註**: 設自動煙感探測與門檻防塵條
`;

// --- Sample Revit CSV Data for Instant Demo ---
const SAMPLE_CSV_CONTENT = `房間編號,房間名稱,門窗編號,門鎖五金編號,牆面粉刷編號,地面粉刷編號,天花粉刷編號,門淨寬cm,開門方向,備註
101,變電站,SD1-A,HD-01,W-01A,FL-03,CL-02,130,外開,高壓配電區
102,變電站,D-99,HD-99,W-01A,FL-01,CL-02,100,內開,備用變電室 (門號與門寬異常)
103,簡報室,D-02,HD-02,W-03,FL-02,CL-01,90,內開,主簡報室
104,機房,SD2-B,HD-03,W-02,FL-01,CL-01,100,外開,空調機房
105,機房,SD2-B,HD-03,W-02,FL-01,CL-01,90,內開,管道機房 (開門方向違規：應外開)
201,廁所,D-05,HD-04,W-04,FL-04,CL-03,95,外開,無障礙廁所 (迴轉150cm)
202,廁所,D-05,HD-02,W-02,FL-04,CL-03,80,內開,男廁 (牆面粉刷與門寬異常)
203,梯廳,FD1-A,HD-05,W-01,FL-05,CL-01,120,雙向,1F 主梯廳
204,辦公室,D-03,HD-02,W-02,FL-02,CL-01,95,內開,專案開發組
205,儲藏室,D-04,HD-06,W-02,FL-01,CL-02,85,內開,行政備品室
206,進氣機房,D-008,HD-03,W-02,FL-01,CL-02,90,外開,進風設備區`;

// --- Application State ---
let spatialRules = [];
let currentQCResults = [];
let chartPassRateInstance = null;
let chartIssueTypesInstance = null;

// --- DOM Loaded Initialization ---
document.addEventListener('DOMContentLoaded', () => {
  initTabs();
  initMarkdownDB(DEFAULT_MD_CONTENT);
  initQCInspector();
  initDynamoGenerator();
  initAutoCADSection();
  initModals();
});

// Toast Notification UX System
function showToast(message, icon = 'fa-circle-check') {
  let container = document.getElementById('toast-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toast-container';
    document.body.appendChild(container);
  }

  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.innerHTML = `<i class="fa-solid ${icon}"></i> <span>${message}</span>`;
  container.appendChild(toast);

  requestAnimationFrame(() => toast.classList.add('show'));

  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => toast.remove(), 300);
  }, 3200);
}

// ==========================================================================
// 1. Navigation & Tabs
// ==========================================================================
function initTabs() {
  const tabBtns = document.querySelectorAll('.tab-btn');
  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      tabBtns.forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));

      btn.classList.add('active');
      const targetId = btn.getAttribute('data-tab');
      const targetEl = document.getElementById(targetId);
      if (targetEl) targetEl.classList.add('active');

      if (targetId === 'tab-analytics') {
        renderAnalyticsCharts();
      }
    });
  });
}

// ==========================================================================
// 2. Markdown Parser & Spatial Database Manager
// ==========================================================================
function initMarkdownDB(mdText) {
  spatialRules = parseMarkdownRules(mdText);
  renderRuleCards(spatialRules);

  // 動態讀取伺服器上的最新 空間裝修與門窗對照表.md 檔案
  fetch('./空間裝修與門窗對照表.md?t=' + Date.now())
    .then(response => {
      if (response.ok) return response.text();
      throw new Error('Network response was not ok');
    })
    .then(liveMdText => {
      if (liveMdText && liveMdText.trim()) {
        spatialRules = parseMarkdownRules(liveMdText);
        renderRuleCards(spatialRules);
        updateDynamoCode();
      }
    })
    .catch(err => {
      console.log('使用預設 Markdown 數據庫內容');
    });

  initRuleManager();
}

function initRuleManager() {
  const searchInput = document.getElementById('rule-search-input');
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      const q = e.target.value.toLowerCase().trim();
      const filtered = spatialRules.filter(r => 
        r.spaceName.toLowerCase().includes(q) ||
        (r.finishCode && r.finishCode.toLowerCase().includes(q)) ||
        (r.doors || []).some(d => d.toLowerCase().includes(q)) ||
        (r.lockHardware && r.lockHardware.toLowerCase().includes(q)) ||
        (r.wallFinish && r.wallFinish.toLowerCase().includes(q)) ||
        (r.floorFinish && r.floorFinish.toLowerCase().includes(q)) ||
        (r.ceilingFinish && r.ceilingFinish.toLowerCase().includes(q)) ||
        (r.notes && r.notes.toLowerCase().includes(q))
      );
      renderRuleCards(filtered);
    });
  }

  const customMdInput = document.getElementById('btn-import-custom-md');
  if (customMdInput) {
    customMdInput.addEventListener('change', (e) => {
      if (e.target.files && e.target.files.length) {
        const file = e.target.files[0];
        const reader = new FileReader();
        reader.onload = (ev) => {
          spatialRules = parseMarkdownRules(ev.target.result);
          renderRuleCards(spatialRules);
          updateDynamoCode();
          showToast(`成功載入自訂規範檔案：「${file.name}」`, 'fa-file-circle-check');
        };
        reader.readAsText(file, 'UTF-8');
      }
    });
  }

  const btnReload = document.getElementById('btn-reload-md');
  if (btnReload) {
    btnReload.addEventListener('click', () => {
      spatialRules = parseMarkdownRules(DEFAULT_MD_CONTENT);
      renderRuleCards(spatialRules);
      updateDynamoCode();
      showToast('已重設恢復為預設 Markdown 規範數據庫', 'fa-rotate-left');
    });
  }

  const btnExportMd = document.getElementById('btn-export-md');
  if (btnExportMd) {
    btnExportMd.addEventListener('click', () => {
      const mdOutput = exportRulesToMarkdown(spatialRules);
      downloadFile(mdOutput, '空間裝修與門窗對照表.md', 'text/markdown');
      showToast('已導出最新空間裝修與門窗對照表.md 檔案', 'fa-arrow-down-to-line');
    });
  }
}

function parseMarkdownRules(mdText) {
  const rules = [];
  const sections = mdText.split(/\n(?=##\s+)/);

  sections.forEach(sec => {
    const lines = sec.trim().split('\n').map(l => l.trim()).filter(l => l);
    if (!lines.length) return;

    const headerMatch = lines[0].match(/^##\s+(.+)$/);
    if (!headerMatch) return;

    const spaceName = headerMatch[1].trim();
    let finishCode = '';
    let doors = [];
    let lockHardware = '';
    let wallFinish = '';
    let floorFinish = '';
    let ceilingFinish = '';
    let notes = '';

    for (let i = 1; i < lines.length; i++) {
      const line = lines[i];
      if (line.startsWith('- **粉刷對照編號**:')) {
        finishCode = line.replace('- **粉刷對照編號**:', '').trim();
      } else if (line.startsWith('- **門窗編號**:')) {
        doors = line.replace('- **門窗編號**:', '').trim().split(',').map(d => d.trim());
      } else if (line.startsWith('- **門鎖五金編號**:') || line.startsWith('- **門鎖五金**:')) {
        lockHardware = line.replace(/- \*\*門鎖五金(編號)?\*\*:/, '').trim();
      } else if (line.startsWith('- **牆面粉刷編號**:')) {
        wallFinish = line.replace('- **牆面粉刷編號**:', '').trim();
      } else if (line.startsWith('- **地面粉刷編號**:')) {
        floorFinish = line.replace('- **地面粉刷編號**:', '').trim();
      } else if (line.startsWith('- **天花粉刷編號**:')) {
        ceilingFinish = line.replace('- **天花粉刷編號**:', '').trim();
      } else if (line.startsWith('- **備註**:')) {
        notes = line.replace('- **備註**:', '').trim();
      }
    }

    let minDoorWidth = 0;
    const wMatch = notes.match(/門寬淨寬需大於\s*(\d+)cm|淨寬需大於\s*(\d+)cm/);
    if (wMatch) {
      minDoorWidth = parseInt(wMatch[1] || wMatch[2], 10);
    }
    const mustOutward = notes.includes('外開門') || notes.includes('向避難方向');

    rules.push({
      spaceName,
      finishCode,
      doors,
      lockHardware,
      wallFinish,
      floorFinish,
      ceilingFinish,
      notes,
      minDoorWidth,
      mustOutward
    });
  });

  return rules;
}

function exportRulesToMarkdown(rules) {
  let md = `# 🏢 建築空間裝修與門窗標準規範數據庫\n\n本資料夾（空間規範數據庫）存放所有空間名稱與門窗編號、粉刷編號、門鎖五金編號之連動對照表。外掛與 QC 工具執行時將自動讀取本資料夾下所有 .md 檔。\n\n---\n\n`;

  rules.forEach(r => {
    md += `## ${r.spaceName}\n`;
    if (r.finishCode) md += `- **粉刷對照編號**: ${r.finishCode}\n`;
    md += `- **門窗編號**: ${r.doors.join(', ')}\n`;
    if (r.lockHardware) md += `- **門鎖五金編號**: ${r.lockHardware}\n`;
    md += `- **牆面粉刷編號**: ${r.wallFinish}\n`;
    md += `- **地面粉刷編號**: ${r.floorFinish}\n`;
    md += `- **天花粉刷編號**: ${r.ceilingFinish}\n`;
    md += `- **備註**: ${r.notes}\n\n`;
  });

  return md;
}

function renderRuleCards(rules) {
  const container = document.getElementById('rule-grid-container');
  if (!container) return;

  if (!rules.length) {
    container.innerHTML = `<div style="grid-column: 1/-1; text-align: center; color: var(--text-muted); padding: 40px;">未搜尋到符合條件的空間規範。</div>`;
    return;
  }

  container.innerHTML = rules.map((r, idx) => `
    <div class="rule-card">
      <div class="rule-card-header">
        <div class="rule-space-title">🏢 ${r.spaceName}</div>
        <div>
          <button class="btn btn-secondary btn-sm" onclick="editRule(${idx})"><i class="fa-solid fa-pen"></i></button>
          <button class="btn btn-danger btn-sm" onclick="deleteRule(${idx})"><i class="fa-solid fa-trash"></i></button>
        </div>
      </div>

      <div class="rule-tag-group">
        ${r.finishCode ? `
        <div class="rule-item">
          <span class="rule-label">🎨 粉刷對照編號:</span>
          <span class="rule-value" style="color: var(--accent-cyan); font-weight: 700;">${r.finishCode}</span>
        </div>` : ''}
        <div class="rule-item">
          <span class="rule-label">🚪 門窗編號:</span>
          <span class="rule-value" style="color: var(--accent-blue); font-weight: 700;">${(r.doors || []).join(', ') || '未設定'}</span>
        </div>
        ${r.lockHardware ? `
        <div class="rule-item">
          <span class="rule-label">🔐 門鎖五金:</span>
          <span class="rule-value">${r.lockHardware}</span>
        </div>` : ''}
        <div class="rule-item">
          <span class="rule-label">🧱 牆面粉刷:</span>
          <span class="rule-value">${r.wallFinish || '未設定'}</span>
        </div>
        <div class="rule-item">
          <span class="rule-label">📐 地面粉刷:</span>
          <span class="rule-value">${r.floorFinish || '未設定'}</span>
        </div>
        <div class="rule-item">
          <span class="rule-label">☁️ 天花粉刷:</span>
          <span class="rule-value">${r.ceilingFinish || '未設定'}</span>
        </div>
      </div>
      ${r.notes ? `<div class="rule-notes"><strong>📌 備註規範:</strong> ${r.notes}</div>` : ''}
    </div>
  `).join('');
}

// Global functions for inline card actions
window.deleteRule = function(index) {
  if (confirm(`確定要刪除「${spatialRules[index].spaceName}」規範？`)) {
    spatialRules.splice(index, 1);
    renderRuleCards(spatialRules);
    updateDynamoCode();
    showToast('已刪除空間規範項目', 'fa-trash');
  }
};

window.editRule = function(index) {
  const r = spatialRules[index];
  const idxEl = document.getElementById('form-rule-index');
  const titleEl = document.getElementById('modal-title');
  const spaceEl = document.getElementById('form-space-name');
  const doorsEl = document.getElementById('form-doors');
  const lockEl = document.getElementById('form-lock-hardware');
  const wallEl = document.getElementById('form-wall');
  const floorEl = document.getElementById('form-floor');
  const ceilEl = document.getElementById('form-ceiling');
  const notesEl = document.getElementById('form-notes');
  const modal = document.getElementById('rule-modal');

  if (idxEl) idxEl.value = index;
  if (titleEl) titleEl.textContent = `編輯規範：${r.spaceName}`;
  if (spaceEl) spaceEl.value = r.spaceName || '';
  if (doorsEl) doorsEl.value = (r.doors || []).join(', ');
  if (lockEl) lockEl.value = r.lockHardware || '';
  if (wallEl) wallEl.value = r.wallFinish || '';
  if (floorEl) floorEl.value = r.floorFinish || '';
  if (ceilEl) ceilEl.value = r.ceilingFinish || '';
  if (notesEl) notesEl.value = r.notes || '';

  if (modal) modal.classList.add('open');
};

// ==========================================================================
// 3. Batch Revit Room QC Inspector Engine
// ==========================================================================
function initQCInspector() {
  const dropzone = document.getElementById('file-dropzone');
  const fileInput = document.getElementById('file-input');

  if (dropzone && fileInput) {
    dropzone.addEventListener('click', () => fileInput.click());
    dropzone.addEventListener('dragover', (e) => {
      e.preventDefault();
      dropzone.classList.add('dragover');
    });
    dropzone.addEventListener('dragleave', () => dropzone.classList.remove('dragover'));
    dropzone.addEventListener('drop', (e) => {
      e.preventDefault();
      dropzone.classList.remove('dragover');
      if (e.dataTransfer.files && e.dataTransfer.files.length) {
        handleCSVFile(e.dataTransfer.files[0]);
      }
    });

    fileInput.addEventListener('change', (e) => {
      if (e.target.files && e.target.files.length) {
        handleCSVFile(e.target.files[0]);
      }
    });
  }

  const btnLoadSample = document.getElementById('btn-load-sample');
  if (btnLoadSample) {
    btnLoadSample.addEventListener('click', () => {
      processCSVString(SAMPLE_CSV_CONTENT);
      showToast('已成功載入測試範例數據', 'fa-vial');
    });
  }

  const filterStatus = document.getElementById('qc-filter-status');
  if (filterStatus) {
    filterStatus.addEventListener('change', (e) => {
      renderQCTable(currentQCResults, e.target.value);
    });
  }

  const btnExportExcel = document.getElementById('btn-export-excel');
  if (btnExportExcel) {
    btnExportExcel.addEventListener('click', () => {
      if (!currentQCResults.length) {
        const sampleRows = parseCSV(SAMPLE_CSV_CONTENT);
        currentQCResults = inspectRevitRooms(sampleRows, spatialRules);
      }
      const timestamp = getTimestampString();
      const filename = `RevitQC_Audit_Report_${timestamp}.xlsx`;
      exportQCReportToExcel(currentQCResults, filename);
    });
  }

  const btnExportReport = document.getElementById('btn-export-report');
  if (btnExportReport) {
    btnExportReport.addEventListener('click', () => {
      if (!currentQCResults.length) {
        const sampleRows = parseCSV(SAMPLE_CSV_CONTENT);
        currentQCResults = inspectRevitRooms(sampleRows, spatialRules);
      }
      const timestamp = getTimestampString();
      const filename = `RevitQC_Audit_Report_${timestamp}.csv`;
      const csvContent = generateQCReportCSV(currentQCResults);
      downloadFile(csvContent, filename, 'text/csv;charset=utf-8;');
      showToast(`成功匯出全新 CSV 報告檔案：「${filename}」`, 'fa-file-csv');
    });
  }
}

function handleCSVFile(file) {
  const reader = new FileReader();
  reader.onload = (e) => {
    processCSVString(e.target.result);
    showToast(`成功讀取 CSV 檔案：「${file.name}」`, 'fa-file-csv');
  };
  reader.readAsText(file, 'UTF-8');
}

function processCSVString(csvText) {
  const rows = parseCSV(csvText);
  if (!rows.length) {
    showToast('❌ CSV 內容無有效數據', 'fa-triangle-exclamation');
    return;
  }

  currentQCResults = inspectRevitRooms(rows, spatialRules);
  updateQCStats(currentQCResults);
  const filterEl = document.getElementById('qc-filter-status');
  renderQCTable(currentQCResults, filterEl ? filterEl.value : 'ALL');
}

function parseCSV(text) {
  const lines = text.trim().split('\n').map(l => l.trim()).filter(l => l);
  if (lines.length < 2) return [];

  const headers = lines[0].replace('\ufeff', '').split(',').map(h => h.trim());
  const dataRows = [];

  for (let i = 1; i < lines.length; i++) {
    const values = lines[i].split(',').map(v => v.trim());
    if (values.length === headers.length) {
      const row = {};
      headers.forEach((h, idx) => {
        row[h] = values[idx];
      });
      dataRows.push(row);
    }
  }

  return dataRows;
}

function inspectRevitRooms(rows, rules) {
  return rows.map(row => {
    const roomId = row['房間編號'] || '';
    const roomName = row['房間名稱'] || '';
    const door = row['門窗編號'] || '';
    const wall = row['牆面粉刷編號'] || '';
    const floor = row['地面粉刷編號'] || '';
    const ceiling = row['天花粉刷編號'] || '';
    const widthStr = row['門淨寬cm'] || '0';
    const swing = row['開門方向'] || '';
    let width = parseFloat(widthStr) || 0;

    // 智慧提取門寬標註 (如 90x210 提取 90cm, 門高自動忽略)
    const mDim = door.match(/(\d+(?:\.\d+)?)\s*[xX*×]\s*\d+/);
    if (mDim && width === 0) {
      width = parseFloat(mDim[1]);
    }

    let matchedRule = rules.find(r => r.spaceName === roomName);
    if (!matchedRule) {
      const matches = rules.filter(r => r.spaceName.includes(roomName) || roomName.includes(r.spaceName));
      if (matches.length > 0) {
        matches.sort((a, b) => b.spaceName.length - a.spaceName.length);
        matchedRule = matches[0];
      }
    }

    const issues = [];
    let status = 'PASS';

    if (!matchedRule) {
      status = 'WARN';
      issues.push(`無對應空間規範規則 (請至資料庫定義「${roomName}」)`);
    } else {
      if (matchedRule.doors && matchedRule.doors.length > 0) {
        const isDoorMatched = matchedRule.doors.some(d => door.includes(d) || d.includes(door));
        if (!isDoorMatched && door) {
          issues.push(`門窗編號不符合規範！實際: ${door}，規範應為: ${matchedRule.doors.join(', ')}`);
        }
      }

      if (matchedRule.wallFinish && wall && !wall.startsWith(matchedRule.wallFinish.split(' ')[0])) {
        issues.push(`牆面粉刷不符！實際: ${wall}，規範應為: ${matchedRule.wallFinish}`);
      }

      if (matchedRule.floorFinish && floor && !floor.startsWith(matchedRule.floorFinish.split(' ')[0])) {
        issues.push(`地面粉刷不符！實際: ${floor}，規範應為: ${matchedRule.floorFinish}`);
      }

      if (matchedRule.ceilingFinish && ceiling && !ceiling.startsWith(matchedRule.ceilingFinish.split(' ')[0])) {
        issues.push(`天花粉刷不符！實際: ${ceiling}，規範應為: ${matchedRule.ceilingFinish}`);
      }

      if (matchedRule.minDoorWidth > 0 && width > 0 && width < matchedRule.minDoorWidth) {
        issues.push(`門淨寬不足！實際: ${width}cm < 規範要求: ${matchedRule.minDoorWidth}cm`);
      }

      if (matchedRule.mustOutward && swing && !swing.includes('外開') && !swing.includes('雙向')) {
        issues.push(`開門方向違規！實際: ${swing}，規範要求需為外開門/避難方向`);
      }

      status = issues.length > 0 ? 'FAIL' : 'PASS';
    }

    return {
      roomId,
      roomName,
      door,
      wall,
      floor,
      ceiling,
      width,
      swing,
      status,
      issues,
      matchedRule: matchedRule ? matchedRule.spaceName : '未匹配'
    };
  });
}

function updateQCStats(results) {
  const total = results.length;
  const pass = results.filter(r => r.status === 'PASS').length;
  const fail = results.filter(r => r.status === 'FAIL').length;
  const rate = total > 0 ? ((pass / total) * 100).toFixed(1) : 0;

  const totalEl = document.getElementById('qc-stat-total');
  const passEl = document.getElementById('qc-stat-pass');
  const failEl = document.getElementById('qc-stat-fail');
  const rateEl = document.getElementById('qc-stat-rate');

  if (totalEl) totalEl.textContent = total;
  if (passEl) passEl.textContent = pass;
  if (failEl) failEl.textContent = fail;
  if (rateEl) rateEl.textContent = `${rate}%`;
}

function renderQCTable(results, filterStatus = 'ALL') {
  const tbody = document.getElementById('qc-table-body');
  if (!tbody) return;

  const filtered = results.filter(r => {
    if (filterStatus === 'ALL') return true;
    return r.status === filterStatus;
  });

  if (!filtered.length) {
    tbody.innerHTML = `
      <tr>
        <td colspan="11" style="text-align: center; color: var(--text-muted); padding: 30px;">
          無相符的 QC 檢核結果記錄
        </td>
      </tr>
    `;
    return;
  }

  tbody.innerHTML = filtered.map(r => {
    let badgeClass = 'warn';
    let badgeText = '⚠️ WARN';
    if (r.status === 'PASS') {
      badgeClass = 'pass';
      badgeText = '✅ PASS';
    } else if (r.status === 'FAIL') {
      badgeClass = 'fail';
      badgeText = '❌ FAIL';
    }

    const issuesHtml = r.issues.length > 0
      ? r.issues.map(i => `<div style="color: var(--status-fail); font-weight: 600;">• ${i}</div>`).join('')
      : `<div style="color: var(--status-pass);">✓ 完全符合規範</div>`;

    return `
      <tr>
        <td style="font-weight: 700; font-family: monospace;">${r.roomId}</td>
        <td><strong>${r.roomName}</strong></td>
        <td><span class="status-badge warn" style="background: rgba(6,182,212,0.1); color: var(--accent-cyan); border-color: rgba(6,182,212,0.3);">${r.matchedRule}</span></td>
        <td>${r.door || '-'}</td>
        <td>${r.wall || '-'}</td>
        <td>${r.floor || '-'}</td>
        <td>${r.ceiling || '-'}</td>
        <td>${r.width ? r.width + ' cm' : '-'}</td>
        <td>${r.status}</td>
        <td><span class="status-badge ${badgeClass}">${badgeText}</span></td>
        <td>${issuesHtml}</td>
      </tr>
    `;
  }).join('');
}

function generateQCReportCSV(results) {
  let csv = '\ufeff房間編號,房間名稱,對應規範條目,門窗編號,牆面粉刷,地面粉刷,天花粉刷,門淨寬cm,開門方向,QC檢核狀態,檢核異常說明\n';
  results.forEach(r => {
    const issueText = r.issues.length > 0 ? r.issues.join('; ') : '完全符合規範';
    csv += `"${r.roomId}","${r.roomName}","${r.matchedRule}","${r.door}","${r.wall}","${r.floor}","${r.ceiling}","${r.width}","${r.swing}","${r.status}","${issueText}"\n`;
  });
  return csv;
}

function getTimestampString() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  const hh = String(now.getHours()).padStart(2, '0');
  const mm = String(now.getMinutes()).padStart(2, '0');
  const ss = String(now.getSeconds()).padStart(2, '0');
  return `${y}${m}${d}_${hh}${mm}${ss}`;
}

function exportQCReportToExcel(results, filename) {
  if (typeof XLSX !== 'undefined') {
    const excelData = results.map(r => ({
      "房間編號": r.roomId,
      "房間名稱": r.roomName,
      "對應規範條目": r.matchedRule,
      "門窗編號": r.door,
      "牆面粉刷": r.wall,
      "地面粉刷": r.floor,
      "天花粉刷": r.ceiling,
      "門淨寬(cm)": r.width || '-',
      "開門方向": r.swing || '-',
      "QC檢核狀態": r.status,
      "檢核異常與建議事項": r.issues.length > 0 ? r.issues.join('; ') : '完全符合規範'
    }));

    const ws = XLSX.utils.json_to_sheet(excelData);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "RevitQC 專案檢核報告");
    
    ws['!cols'] = [
      { wch: 10 }, { wch: 16 }, { wch: 16 }, { wch: 14 },
      { wch: 14 }, { wch: 14 }, { wch: 14 }, { wch: 12 },
      { wch: 10 }, { wch: 12 }, { wch: 45 }
    ];

    XLSX.writeFile(wb, filename);
    showToast(`成功匯出全新 Excel 報告：「${filename}」`, 'fa-file-excel');
  } else {
    const csvContent = generateQCReportCSV(results);
    downloadFile(csvContent, filename.replace('.xlsx', '.csv'), 'text/csv;charset=utf-8;');
  }
}

// ==========================================================================
// 4. Revit Dynamo Python Code Generator Engine
// ==========================================================================
function initDynamoGenerator() {
  updateDynamoCode();
  const radAuto = document.getElementById('rad-mode-auto');
  const radUpdate = document.getElementById('rad-mode-update');
  if (radAuto) radAuto.addEventListener('change', updateDynamoCode);
  if (radUpdate) radUpdate.addEventListener('change', updateDynamoCode);

  const btnCopyDynamo = document.getElementById('btn-copy-dynamo');
  if (btnCopyDynamo) btnCopyDynamo.addEventListener('click', copyDynamoCode);

  const btnCopyFloating = document.getElementById('btn-copy-code-floating');
  if (btnCopyFloating) btnCopyFloating.addEventListener('click', copyDynamoCode);

  const btnDownloadParams = document.getElementById('btn-download-shared-params');
  if (btnDownloadParams) {
    btnDownloadParams.addEventListener('click', () => {
      const paramsContent = `# This is a Revit shared parameter file.\n# Do not edit manually.\n*META\tVERSION\t2.0\n*GROUP\tID\tNAME\nGROUP\t1\tRevitQC裝修規範組\n*PARAM\tGUID\tNAME\tDATATYPE\tDATACATEGORY\tGROUP\tVISIBLE\tDESCRIPTION\tUSERMODIFIABLE\tHIDEWHENNOVALUE\nPARAM\t8f90c8a1-6a23-455b-8d12-1234567890ab\tQC_Status\tTEXT\t\t1\t1\tQC檢核合規狀態\t1\t0\nPARAM\t7b81c9b2-7b34-566c-9e23-2345678901bc\tQC_Issues\tTEXT\t\t1\t1\tQC檢核違規說明\t1\t0\nPARAM\t6a72d0c3-8c45-677d-af34-3456789012cd\tTarget_WallFinish\tTEXT\t\t1\t1\t目標牆面粉刷\t1\t0\nPARAM\t5b63e1d4-9d56-788e-b045-4567890123de\tTarget_FloorFinish\tTEXT\t\t1\t1\t目標地面粉刷\t1\t0\nPARAM\t4a54f2e5-0e67-899f-c156-5678901234ef\tTarget_CeilingFinish\tTEXT\t\t1\t1\t目標天花粉刷\t1\t0\nPARAM\t3a45a3f6-1f78-900a-d267-6789012345fa\tTarget_LockHardware\tTEXT\t\t1\t1\t目標門鎖五金\t1\t0\n`;
      downloadFile(paramsContent, 'RevitQC_SharedParameters.txt', 'text/plain');
      showToast('已下載 Revit 共用參數定義檔', 'fa-download');
    });
  }

  const btnDownloadPyrevit = document.getElementById('btn-download-pyrevit');
  if (btnDownloadPyrevit) {
    btnDownloadPyrevit.addEventListener('click', () => {
      const scriptContent = `# -*- coding: utf-8 -*-\n__title__ = "空間規範\\n檢核對照"\n__doc__ = "一鍵比對專案房間粉刷與門窗五金對照表"\n\nfrom pyrevit import script, forms\nprint("RevitQC pyRevit Tool Ready!")\n`;
      downloadFile(scriptContent, 'pyrevit_script.py', 'text/plain');
      showToast('已下載 pyRevit 工具按鈕腳本', 'fa-download');
    });
  }
}

function updateDynamoCode() {
  const codeBlock = document.getElementById('dynamo-code-block');
  if (!codeBlock) return;

  const modeAuto = document.getElementById('rad-mode-auto')?.checked ?? true;
  const rulesJson = JSON.stringify(spatialRules, null, 4);

  let pyCode = '';
  if (modeAuto) {
    pyCode = `# -*- coding: utf-8 -*-
# ==============================================================================
# Revit Dynamo Python Script: 規範自動寫入 (Auto-Write Specification Mode)
# ==============================================================================

import clr
clr.AddReference('RevitServices')
clr.AddReference('RevitAPI')

from RevitServices.Persistence import DocumentManager
from RevitServices.Transactions import TransactionManager
from Autodesk.Revit.DB import FilteredElementCollector, BuiltInCategory

doc = DocumentManager.Instance.CurrentDBDocument
SPATIAL_RULES = ${rulesJson}

rooms = FilteredElementCollector(doc).OfCategory(BuiltInCategory.OST_Rooms).ToElements()

TransactionManager.Instance.EnsureInTransaction(doc)
updated_count = 0

for room in rooms:
    r_name = room.LookupParameter("名稱").AsString() if room.LookupParameter("名稱") else ""
    rule = next((r for r in SPATIAL_RULES if r["spaceName"] in r_name or r_name in r["spaceName"]), None)
    
    if rule:
        p_wall = room.LookupParameter("牆面粉刷")
        p_floor = room.LookupParameter("地面粉刷")
        p_ceil = room.LookupParameter("天花板粉刷")
        
        if p_wall and not p_wall.IsReadOnly and rule["wallFinish"]:
            p_wall.Set(rule["wallFinish"])
        if p_floor and not p_floor.IsReadOnly and rule["floorFinish"]:
            p_floor.Set(rule["floorFinish"])
        if p_ceil and not p_ceil.IsReadOnly and rule["ceilingFinish"]:
            p_ceil.Set(rule["ceilingFinish"])
            
        updated_count += 1

TransactionManager.Instance.TransactionTaskDone()
OUT = "✅ 已成功更新 " + str(updated_count) + " 個房間的裝修粉刷規範參數！"
`;
  } else {
    pyCode = `# -*- coding: utf-8 -*-
# ==============================================================================
# Revit Dynamo Python Script: 空間數據自動 QC 檢查器
# ==============================================================================

import clr
clr.AddReference('RevitServices')
clr.AddReference('RevitAPI')

from RevitServices.Persistence import DocumentManager
from RevitServices.Transactions import TransactionManager
from Autodesk.Revit.DB import FilteredElementCollector, BuiltInCategory

doc = DocumentManager.Instance.CurrentDBDocument
SPATIAL_RULES = ${rulesJson}

rooms = FilteredElementCollector(doc).OfCategory(BuiltInCategory.OST_Rooms).ToElements()

results = []
TransactionManager.Instance.EnsureInTransaction(doc)

for room in rooms:
    r_name = room.LookupParameter("名稱").AsString() if room.LookupParameter("名稱") else ""
    w_val = room.LookupParameter("牆面粉刷").AsString() if room.LookupParameter("牆面粉刷") else ""
    f_val = room.LookupParameter("地面粉刷").AsString() if room.LookupParameter("地面粉刷") else ""
    
    rule = next((r for r in SPATIAL_RULES if r["spaceName"] in r_name or r_name in r["spaceName"]), None)
    
    if rule:
        issues = []
        if rule["wallFinish"] and not rule["wallFinish"].startswith(w_val):
            issues.append("牆面粉刷不符")
        if rule["floorFinish"] and not rule["floorFinish"].startswith(f_val):
            issues.append("地面粉刷不符")

        p_qc = room.LookupParameter("QC狀態")
        if p_qc and not p_qc.IsReadOnly:
            if issues:
                p_qc.Set("FAIL: " + ", ".join(issues))
            else:
                p_qc.Set("PASS")
        
        results.append(r_name + ": " + ("FAIL" if issues else "PASS"))

TransactionManager.Instance.TransactionTaskDone()
OUT = results
`;
  }

  codeBlock.textContent = pyCode;
}

function copyDynamoCode() {
  const codeBlock = document.getElementById('dynamo-code-block');
  if (!codeBlock) return;
  navigator.clipboard.writeText(codeBlock.textContent).then(() => {
    showToast('已成功複製 Revit Dynamo Python 程式碼至剪貼簿！', 'fa-copy');
  });
}

// ==========================================================================
// 5. Modals & Helpers
// ==========================================================================
function initModals() {
  const modal = document.getElementById('rule-modal');
  const btnOpen = document.getElementById('btn-open-add-modal');
  const btnClose = document.getElementById('btn-close-modal');
  const btnCancel = document.getElementById('btn-cancel-modal');
  const form = document.getElementById('rule-form');

  if (!modal || !form) return;

  const openModalFunc = () => {
    const idxEl = document.getElementById('form-rule-index');
    const titleEl = document.getElementById('modal-title');
    if (idxEl) idxEl.value = '-1';
    if (titleEl) titleEl.textContent = '新增空間規範項目';
    form.reset();
    modal.classList.add('open');
  };

  if (btnOpen) btnOpen.addEventListener('click', openModalFunc);

  const btnFloating = document.getElementById('btn-add-rule-floating');
  if (btnFloating) btnFloating.addEventListener('click', openModalFunc);

  const closeModal = () => modal.classList.remove('open');
  if (btnClose) btnClose.addEventListener('click', closeModal);
  if (btnCancel) btnCancel.addEventListener('click', closeModal);

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const idxEl = document.getElementById('form-rule-index');
    const idx = idxEl ? parseInt(idxEl.value, 10) : -1;
    const spaceName = (document.getElementById('form-space-name')?.value || '').trim();
    const doors = (document.getElementById('form-doors')?.value || '').split(',').map(d => d.trim()).filter(d => d);
    const lockHardware = (document.getElementById('form-lock-hardware')?.value || '').trim();
    const wallFinish = (document.getElementById('form-wall')?.value || '').trim();
    const floorFinish = (document.getElementById('form-floor')?.value || '').trim();
    const ceilingFinish = (document.getElementById('form-ceiling')?.value || '').trim();
    const notes = (document.getElementById('form-notes')?.value || '').trim();

    if (!spaceName) {
      alert('請輸入空間名稱！');
      return;
    }

    let minDoorWidth = 0;
    const wMatch = notes.match(/門寬淨寬需大於\s*(\d+)cm|淨寬需大於\s*(\d+)cm/);
    if (wMatch) {
      minDoorWidth = parseInt(wMatch[1] || wMatch[2], 10);
    }
    const mustOutward = notes.includes('外開門') || notes.includes('向避難方向');

    const newRule = {
      spaceName,
      finishCode: spatialRules[idx] ? spatialRules[idx].finishCode : '',
      doors,
      lockHardware,
      wallFinish,
      floorFinish,
      ceilingFinish,
      notes,
      minDoorWidth,
      mustOutward
    };

    if (idx >= 0 && idx < spatialRules.length) {
      spatialRules[idx] = newRule;
      showToast(`已成功更新空間規範：「${spaceName}」`, 'fa-circle-check');
    } else {
      spatialRules.push(newRule);
      showToast(`已成功新增空間規範：「${spaceName}」`, 'fa-circle-check');
    }

    renderRuleCards(spatialRules);
    updateDynamoCode();
    closeModal();
  });
}

function downloadFile(content, fileName, contentType) {
  const a = document.createElement('a');
  const file = new Blob(['\ufeff' + content], { type: contentType });
  a.href = URL.createObjectURL(file);
  a.download = fileName;
  a.click();
  URL.revokeObjectURL(a.href);
}

// ==========================================================================
// 6. Chart.js Analytics Dashboard
// ==========================================================================
function renderAnalyticsCharts() {
  const passEl = document.getElementById('chart-pass-rate');
  const issueEl = document.getElementById('chart-issue-types');

  if (!passEl || !issueEl) return;

  if (!currentQCResults.length) {
    const sampleRows = parseCSV(SAMPLE_CSV_CONTENT);
    currentQCResults = inspectRevitRooms(sampleRows, spatialRules);
  }

  const passCount = currentQCResults.filter(r => r.status === 'PASS').length;
  const failCount = currentQCResults.filter(r => r.status === 'FAIL').length;
  const warnCount = currentQCResults.filter(r => r.status === 'WARN').length;

  const ctxPass = passEl.getContext('2d');
  if (chartPassRateInstance) chartPassRateInstance.destroy();

  chartPassRateInstance = new Chart(ctxPass, {
    type: 'doughnut',
    data: {
      labels: ['✅ PASS 完全符合', '❌ FAIL 違規', '⚠️ WARN 未定義規範'],
      datasets: [{
        data: [passCount, failCount, warnCount],
        backgroundColor: ['#10b981', '#ef4444', '#f59e0b'],
        borderWidth: 0
      }]
    },
    options: {
      responsive: true,
      plugins: {
        legend: {
          labels: { color: '#f8fafc', font: { family: 'Inter', size: 12 } }
        }
      }
    }
  });

  const issueCounts = {
    '門窗編號不符': 0,
    '牆面粉刷不符': 0,
    '地面粉刷不符': 0,
    '天花粉刷不符': 0,
    '門淨寬不足': 0,
    '開門方向違規': 0
  };

  currentQCResults.forEach(r => {
    r.issues.forEach(iss => {
      if (iss.includes('門窗編號')) issueCounts['門窗編號不符']++;
      if (iss.includes('牆面粉刷')) issueCounts['牆面粉刷不符']++;
      if (iss.includes('地面粉刷')) issueCounts['地面粉刷不符']++;
      if (iss.includes('天花粉刷')) issueCounts['天花粉刷不符']++;
      if (iss.includes('淨寬')) issueCounts['門淨寬不足']++;
      if (iss.includes('開門方向')) issueCounts['開門方向違規']++;
    });
  });

  const ctxIssue = issueEl.getContext('2d');
  if (chartIssueTypesInstance) chartIssueTypesInstance.destroy();

  chartIssueTypesInstance = new Chart(ctxIssue, {
    type: 'bar',
    data: {
      labels: Object.keys(issueCounts),
      datasets: [{
        label: '異常計數',
        data: Object.values(issueCounts),
        backgroundColor: 'rgba(6, 182, 212, 0.7)',
        borderColor: '#06b6d4',
        borderWidth: 1,
        borderRadius: 6
      }]
    },
    options: {
      responsive: true,
      scales: {
        y: {
          ticks: { color: '#94a3b8', stepSize: 1 },
          grid: { color: 'rgba(255, 255, 255, 0.05)' }
        },
        x: {
          ticks: { color: '#f8fafc' },
          grid: { display: false }
        }
      },
      plugins: {
        legend: { display: false }
      }
    }
  });
}

// ==========================================================================
// 7. AutoCAD (CAD) Integration Engine
// ==========================================================================
function initAutoCADSection() {
  fetch('./cad_qc.lsp?t=' + Date.now())
    .then(res => {
      if (res.ok) return res.text();
      throw new Error('LSP fetch failed');
    })
    .then(lispText => {
      if (lispText && lispText.trim()) {
        const block = document.getElementById('lisp-code-block');
        if (block) block.textContent = lispText;

        const btnCopy = document.getElementById('btn-copy-lisp');
        if (btnCopy) {
          btnCopy.addEventListener('click', () => {
            navigator.clipboard.writeText(lispText).then(() => {
              showToast('已成功複製最新的 AutoCAD AutoLISP 程式碼至剪貼簿！', 'fa-copy');
            });
          });
        }

        const btnDownload = document.getElementById('btn-download-autolisp');
        if (btnDownload) {
          btnDownload.addEventListener('click', () => {
            downloadFile(lispText, 'cad_qc.lsp', 'text/plain');
            showToast('已下載 AutoCAD AutoLISP 腳本 (cad_qc.lsp)', 'fa-download');
          });
        }
      }
    })
    .catch(err => {
      console.log('使用預載 LISP 內容');
    });
}
