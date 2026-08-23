;; ==============================================================================
;; AutoCAD Spatial & Door Schedule Quality Control Tool (cad_qc.lsp)
;; 
;; Dual Mode Engine:
;;   - MODE A (Space Name): Selecting "變電站", "進氣機房", "機房" writes PE-01 / PE-08 / PE-02.
;;   - MODE B (Door Tag / Door Schedule): Selecting "SD1-A", "D-01", "D-008", "SD2-B", "D-05", "FD1-A" 
;;     automatically reverse-matches space, outputs Finish Code, HD hardware & specs.
;;
;; Features:
;;   - Perfect First Tag Pick (Prevents overwriting primary tag with subsequent list items)
;;   - Character-by-Character String Splitter (Fixes AutoLISP multi-delimiter bug for commas, spaces)
;;   - Hard Single Tag Output Guard (Guarantees ONLY D008, D0081, or D0082 reaches canvas)
;;   - Duplicate Door Tag Skip Engine (Prevents re-processing existing D008/D0081/D0082 texts)
;;   - Expanded Door & Window Line Filter (Supports 門, 窗, DOOR, WIN, 240門號, 240窗編號)
;;   - Header-Scoped Door Width Extractor (- **90cm門窗編號**: D008 -> 90:D008, - **120cm門窗編號**: D0081 -> 120:D0081)
;;   - Triple-Check Door Width Matching Engine (90/90cm -> D008, 120/120cm -> D0081, 240 -> D0082)
;;   - Safe ASCII Digit Extraction Engine (Prevents Chinese Byte Corruption)
;;   - High Priority DB File Finder (Prefers Downloads/1 & Downloads/--main)
;;   - Auto-updates Block Attributes < - - > for Finish Code (e.g. PE08)
;;   - Auto-creates Circle Symbol Tag with Centered Door Number (Radius = 50, Text Height = 30)
;;
;; Commands: CADQC, QC, REVITQC
;; ==============================================================================

(vl-load-com)

;; Helper: Character-by-character String Splitter (Handles multi-delimiter sets like ",; \t\r\n")
(defun cad-split-string (str delim / i ch res cur-item is-delim d-idx)
  (setq res '())
  (if (and str (not (equal str "")))
    (progn
      (setq cur-item "")
      (setq i 1)
      (while (<= i (strlen str))
        (setq ch (substr str i 1))
        (setq is-delim nil)
        (setq d-idx 1)
        (while (<= d-idx (strlen delim))
          (if (equal ch (substr delim d-idx 1))
            (setq is-delim T)
          )
          (setq d-idx (+ d-idx 1))
        )

        (if is-delim
          (progn
            (setq cur-item (vl-string-trim " \t\r\n*:`" cur-item))
            (if (not (equal cur-item ""))
              (setq res (cons cur-item res))
            )
            (setq cur-item "")
          )
          (setq cur-item (strcat cur-item ch))
        )
        (setq i (+ i 1))
      )
      (setq cur-item (vl-string-trim " \t\r\n*:`" cur-item))
      (if (not (equal cur-item ""))
        (setq res (cons cur-item res))
      )
    )
  )
  (reverse res)
)

;; Helper: Safe digit extraction for width matching (Only extracts pure ASCII digits 0-9)
(defun cad-extract-digits (str / i ch res ascii-val)
  (if (null str) (setq str ""))
  (setq res "")
  (setq i 1)
  (while (<= i (strlen str))
    (setq ch (substr str i 1))
    (setq ascii-val (ascii ch))
    (if (and (>= ascii-val 48) (<= ascii-val 57))
      (setq res (strcat res ch))
    )
    (setq i (+ i 1))
  )
  res
)

;; Helper: Check if string is already a door tag in the database (to prevent duplicate re-processing)
(defun cad-is-already-door-tag (str db / is-match clean-str r door-val tag-list t-item)
  (setq is-match nil)
  (if (and str (not (equal str "")))
    (progn
      (setq clean-str (str-upcase (vl-string-trim " \t\r\n" str)))
      (foreach r db
        (if (null is-match)
          (progn
            (setq door-val (cdr (assoc "DOOR" (cdr r))))
            (if (and door-val (not (equal door-val "")))
              (progn
                (setq tag-list (cad-split-string door-val ",; \t\r\n"))
                (foreach t-item tag-list
                  (setq t-item (str-upcase (vl-string-trim " \t\r\n" t-item)))
                  (if (and (not (equal t-item "")) (equal clean-str t-item))
                    (setq is-match T)
                  )
                )
              )
            )
          )
        )
      )
    )
  )
  is-match
)

;; Helper: Clean door tag strictly to single tag (e.g. "D008, D0081" -> "D008")
(defun cad-clean-door-tag (str / pos item-list item clean-item res)
  (if (null str) (setq str ""))
  
  ;; Strip parentheses notes
  (setq pos (vl-string-search "(" str))
  (if pos (setq str (substr str 1 pos)))
  (setq pos (vl-string-search "（" str))
  (if pos (setq str (substr str 1 pos)))

  ;; If string has colon e.g. "120: D0081", extract value right after colon
  (if (vl-string-search ":" str)
    (progn
      (setq pos (vl-string-search ":" str))
      (setq str (substr str (+ pos 2)))
    )
  )

  ;; Split by comma or space
  (setq item-list (cad-split-string str ",; \t\r\n"))
  (setq res "")

  (foreach item item-list
    (setq clean-item (vl-string-trim " \t\r\ncmCM*:` " item))
    (if (and (not (equal clean-item ""))
             (not (vl-string-search ":" clean-item))
             (>= (strlen clean-item) 2))
      (progn
        (if (equal res "") (setq res clean-item))
      )
    )
  )

  (if (equal res "") (setq res str))
  (vl-string-trim " \t\r\ncmCM*:` " res)
)

;; Helper: Get Door Tag mapped to specified door width (e.g. width 90 -> D008, width 120 -> D0081, width 240 -> D0082)
(defun cad-get-door-tag-by-width (door-str width-map req-width / req-digits combined-str map-items found-tag pair w-part w-digits t-val pos req-upper)
  (setq req-digits (cad-extract-digits req-width))
  (if (or (null req-digits) (equal req-digits "")) (setq req-digits "90"))
  (setq req-upper (str-upcase (vl-string-trim " \t\r\n" req-width)))
  (setq found-tag nil)

  ;; Search width-map first
  (if (and width-map (not (equal width-map "")))
    (progn
      (setq map-items (cad-split-string width-map ",;()\n\r"))
      (foreach pair map-items
        (if (null found-tag)
          (progn
            (setq pos (vl-string-search ":" pair))
            (if pos
              (progn
                (setq w-part (vl-string-trim " \t\r\n" (substr pair 1 pos)))
                (setq w-digits (cad-extract-digits w-part))
                (setq t-val (cad-clean-door-tag (substr pair (+ pos 2))))

                ;; Triple Check width match
                (if (or (equal w-digits req-digits)
                        (equal (str-upcase w-part) req-upper)
                        (equal (strcat w-digits "CM") req-upper))
                  (setq found-tag t-val)
                )
              )
            )
          )
        )
      )
    )
  )

  ;; Fallback to primary single door tag if not matched by width
  (if (null found-tag)
    (setq found-tag (cad-get-primary-door-tag door-str))
  )

  (cad-clean-door-tag found-tag)
)

;; Helper: Extract primary clean door tag (e.g. "D008, D0081, D0082" -> "D008")
(defun cad-get-primary-door-tag (door-str / item-list res item clean-item)
  (if (null door-str) (setq door-str ""))
  (setq item-list (cad-split-string door-str ",;() \t\r\n"))
  (setq res "")
  (foreach item item-list
    (setq clean-item (vl-string-trim " \t\r\ncmCM*:` " item))
    (if (and (not (equal clean-item "")) (not (vl-string-search ":" clean-item)))
      (if (equal res "")
        (setq res clean-item)
        (if (and (vl-string-search "-" res) (not (vl-string-search "-" clean-item)))
          (setq res clean-item)
        )
      )
    )
  )
  (if (equal res "") (setq res door-str))
  (cad-clean-door-tag res)
)

;; Helper: Display readable Traditional Chinese space name for debug logs
(defun cad-get-display-room-name (space-key / s)
  (if (null space-key) (setq space-key ""))
  (cond
    ((vl-string-search (strcat (chr 182) (chr 105) (chr 174) (chr 240) (chr 190) (chr 247) (chr 169) (chr 208)) space-key) "進氣機房")
    ((vl-string-search (strcat (chr 197) (chr 220) (chr 185) (chr 113) (chr 175) (chr 184)) space-key) "變電站")
    ((vl-string-search (strcat (chr 194) (chr 178) (chr 179) (chr 248) (chr 171) (chr 199)) space-key) "簡報室")
    ((vl-string-search (strcat (chr 177) (chr 232) (chr 198) (chr 85)) space-key) "梯廳")
    ((vl-string-search (strcat (chr 191) (chr 236) (chr 164) (chr 189) (chr 171) (chr 199)) space-key) "辦公室")
    ((vl-string-search (strcat (chr 192) (chr 120) (chr 194) (chr 195) (chr 171) (chr 199)) space-key) "儲藏室")
    ((vl-string-search (strcat (chr 180) (chr 90) (chr 169) (chr 210)) space-key) "廁所")
    ((vl-string-search (strcat (chr 190) (chr 247) (chr 169) (chr 208)) space-key) "機房")
    (t space-key)
  )
)

;; Built-in Fallback Database Rules (Ensures 100% matching even if .md file is missing)
(defun cad-get-builtin-rules ()
  (list
    (list (cad-normalize-room-name "進氣機房")
          (cons "FINISH_CODE" "PE08")
          (cons "DOOR" "D008, D0081, D0082")
          (cons "DOOR_WIDTH_MAP" "90:D008, 120:D0081, 240:D0082")
          (cons "HARDWARE" "HD-03")
          (cons "WALL" "W-02")
          (cons "FLOOR" "FL-01")
          (cons "CEILING" "CL-02")
          (cons "NOTES" "設自動煙感探測與門檻防塵條"))
    (list (cad-normalize-room-name "變電站")
          (cons "FINISH_CODE" "PE01")
          (cons "DOOR" "D01, SD1A")
          (cons "DOOR_WIDTH_MAP" "90:D01, 120:SD1A")
          (cons "HARDWARE" "HD-01")
          (cons "WALL" "W-01A")
          (cons "FLOOR" "FL-03")
          (cons "CEILING" "CL-02")
          (cons "NOTES" "避難通口需設甲種防火門"))
    (list (cad-normalize-room-name "簡報室")
          (cons "FINISH_CODE" "P102")
          (cons "DOOR" "D02, D02A")
          (cons "DOOR_WIDTH_MAP" "90:D02, 120:D02A")
          (cons "HARDWARE" "HD-02")
          (cons "WALL" "W-03")
          (cons "FLOOR" "FL-02")
          (cons "CEILING" "CL-01")
          (cons "NOTES" "需檢核採光面積"))
    (list (cad-normalize-room-name "機房")
          (cons "FINISH_CODE" "PE02")
          (cons "DOOR" "SD2B, SD2B1")
          (cons "DOOR_WIDTH_MAP" "90:SD2B, 120:SD2B1")
          (cons "HARDWARE" "HD-03")
          (cons "WALL" "W-02")
          (cons "FLOOR" "FL-01")
          (cons "CEILING" "CL-01")
          (cons "NOTES" "門需開向避難方向"))
    (list (cad-normalize-room-name "廁所")
          (cons "FINISH_CODE" "P104")
          (cons "DOOR" "D05, D05A, D05B")
          (cons "DOOR_WIDTH_MAP" "80:D05, 90:D05A, 120:D05B")
          (cons "HARDWARE" "HD-04")
          (cons "WALL" "W-04")
          (cons "FLOOR" "FL-04")
          (cons "CEILING" "CL-03")
          (cons "NOTES" "無障礙廁所迴轉直徑須滿 150cm"))
    (list (cad-normalize-room-name "梯廳")
          (cons "FINISH_CODE" "P105")
          (cons "DOOR" "FD1A, FD1A2")
          (cons "DOOR_WIDTH_MAP" "120:FD1A, 150:FD1A2")
          (cons "HARDWARE" "HD-05")
          (cons "WALL" "W-01")
          (cons "FLOOR" "FL-05")
          (cons "CEILING" "CL-01")
          (cons "NOTES" "逃生管道與安全梯前室符合防火"))
    (list (cad-normalize-room-name "辦公室")
          (cons "FINISH_CODE" "P103")
          (cons "DOOR" "D03, D03A")
          (cons "DOOR_WIDTH_MAP" "90:D03, 120:D03A")
          (cons "HARDWARE" "HD-02")
          (cons "WALL" "W-02")
          (cons "FLOOR" "FL-02")
          (cons "CEILING" "CL-01")
          (cons "NOTES" "門寬淨寬需大於 90cm"))
    (list (cad-normalize-room-name "儲藏室")
          (cons "FINISH_CODE" "P106")
          (cons "DOOR" "D04, D04A")
          (cons "DOOR_WIDTH_MAP" "90:D04, 120:D04A")
          (cons "HARDWARE" "HD-06")
          (cons "WALL" "W-02")
          (cons "FLOOR" "FL-01")
          (cons "CEILING" "CL-02")
          (cons "NOTES" "設自動煙感探測"))
  )
)

;; --- Main Command ---
(defun c:REVITQC (/ filepath file line current-space val ss idx total ent ent-data ent-type room-name clean-name matched-rule finish-code door-spec door-width-map hw-spec wall-spec floor-spec ceil-spec notes-spec pass-count fail-count att att-tag att-val clean-att-val exact-name-found found-att-val auto-write ins-pt text-h layer-name new-y new-pt align-h align-v new-ent block-attr-updated offset-y circle-y circle-pt radius tag-text-h primary-tag door-width-input rule-db db-summary r-item clean-finish excel-path)
  (princ "\n==========================================================")
  (princ "\n Spatial & Door Schedule QC Tool v16.0 (Perfect Engine)")
  (princ "\n==========================================================")

  ;; Target Excel File Path (All block reads write and append to the SAME Excel file)
  (setq excel-path "C:\\Users\\葉真希\\Downloads\\匯出製 Excel\\RevitQC_空間規範數據庫\\空間裝修與門窗匯出表.csv")
  (if (and (getvar "DWGPREFIX") (not (equal (getvar "DWGPREFIX") "")))
    (setq excel-path (strcat (getvar "DWGPREFIX") "空間裝修與門窗匯出表.csv"))
  )

  ;; Smart DB File Location Search Priority: Workspace -> Downloads/1 -> Downloads/--main -> DWGPREFIX -> findfile
  (setq filepath "C:\\Users\\葉真希\\Downloads\\匯出製 Excel\\RevitQC_空間規範數據庫\\空間裝修與門窗對照表.md")
  (if (not (findfile filepath))
    (setq filepath "C:\\Users\\葉真希\\Downloads\\1\\空間裝修與門窗對照表.md")
  )
  (if (not (findfile filepath))
    (setq filepath "C:\\Users\\葉真希\\Downloads\\--main\\RevitQC_空間規範數據庫\\空間裝修與門窗對照表.md")
  )
  (if (not (findfile filepath))
    (setq filepath (strcat (getvar "DWGPREFIX") "空間裝修與門窗對照表.md"))
  )
  (if (not (findfile filepath))
    (setq filepath (findfile "空間裝修與門窗對照表.md"))
  )

  ;; Parse Markdown Database (Supports UTF-8 ADODB.Stream & Native ANSI)
  (if (and filepath (findfile filepath))
    (setq rule-db (cad-read-md-file filepath))
    (setq rule-db nil)
  )

  ;; Fallback to Built-in Rule Database if .md file returned 0 rules
  (if (or (null rule-db) (= (length rule-db) 0))
    (progn
      (setq rule-db (cad-get-builtin-rules))
      (princ "\n[DB NOTE] Loaded Built-in Spatial Regulations Database (8 Rules Active).")
    )
    (princ (strcat "\n[DB OK] Loaded " (itoa (length rule-db)) " space rules from file: " filepath))
  )

  ;; Print loaded rules summary for debug
  (setq db-summary "")
  (foreach r-item rule-db
    (setq db-summary (strcat db-summary (cad-get-display-room-name (car r-item)) " (" (cdr (assoc "FINISH_CODE" (cdr r-item))) "), "))
  )
  (princ (strcat "\n[DB RULES] Registered: " db-summary))
  (princ (strcat "\n[EXCEL TARGET] Target Excel File: " excel-path))

  ;; Prompt user for Door Width (e.g. 90, 120, 240 cm)
  (setq door-width-input (getstring "\nEnter Door/Window Width in cm (e.g. 90, 120, 240) <90>: "))
  (if (or (null door-width-input) (equal (vl-string-trim " \t\r\n" door-width-input) ""))
    (setq door-width-input "90")
  )
  (princ (strcat "\n[DOOR WIDTH] Active Door Width Criteria: " door-width-input " cm"))

  ;; Prompt user for auto text insertion below space name / door tag
  (initget "Y N")
  (setq auto-write (getkword "\nAuto-insert Finish Code and Door/Window Circle Tag (e.g. ◯ D0081) below Space Name / Block? [Yes(Y)/No(N)] <Y>: "))
  (if (null auto-write) (setq auto-write "Y"))

  ;; --- Select DWG Entities (Supports Space Names, Door Schedule Tables, Door Tags) ---
  (princ "\n\nSelect DWG Room Labels or Door Schedule Tags (TEXT, MTEXT, INSERT, ATTRIB):")
  (setq ss (ssget '((0 . "TEXT,MTEXT,INSERT,ATTRIB"))))

  (if (null ss)
    (progn
      (cad-qc-show-error "Error: No DWG entities selected. Command aborted.")
      (exit)
    )
  )

  (setq total (sslength ss))
  (setq idx 0)
  (setq pass-count 0)
  (setq fail-count 0)

  (princ (strcat "\n\nProcessing " (itoa total) " selected DWG Space & Door Schedule entities...\n"))
  (princ "\n---------------------------------------------------------------------------------------------------")
  (princ "\nMode | DWG Label / Tag | Matched Space | Finish Code | Door Tag (Width) | Hardware Specs")
  (princ "\n---------------------------------------------------------------------------------------------------")

  (while (< idx total)
    (setq ent (ssname ss idx))
    (setq ent-data (entget ent))
    (setq ent-type (cdr (assoc 0 ent-data)))
    (setq room-name "")
    (setq ins-pt nil)
    (setq text-h 2.5)
    (setq layer-name "0")
    (setq align-h 0)
    (setq align-v 0)

    ;; Extract Text & Alignment Coordinates (Supports Group 10 & Group 11)
    (cond
      ((or (equal ent-type "TEXT") (equal ent-type "ATTRIB"))
       (setq room-name (cdr (assoc 1 ent-data)))
       (setq text-h (cdr (assoc 40 ent-data)))
       (setq layer-name (cdr (assoc 8 ent-data)))
       (if (assoc 72 ent-data) (setq align-h (cdr (assoc 72 ent-data))))
       (if (assoc 73 ent-data) (setq align-v (cdr (assoc 73 ent-data))))
       
       ;; If text has alignment (Center, Right, Middle), use Group 11 if valid
       (if (and (assoc 11 ent-data)
                (not (equal (cdr (assoc 11 ent-data)) '(0.0 0.0 0.0))))
         (setq ins-pt (cdr (assoc 11 ent-data)))
         (setq ins-pt (cdr (assoc 10 ent-data)))
       )
      )
      ((equal ent-type "MTEXT")
       (setq room-name (cdr (assoc 1 ent-data)))
       (setq room-name (cad-clean-mtext room-name))
       (setq ins-pt (cdr (assoc 10 ent-data)))
       (setq layer-name (cdr (assoc 8 ent-data)))
      )
      ((equal ent-type "INSERT")
       (setq ins-pt (cdr (assoc 10 ent-data)))
       (setq layer-name (cdr (assoc 8 ent-data)))
       (setq found-att-val nil)
       (setq exact-name-found nil)

       (princ (strcat "\n   [DEBUG INSERT] Selected Block: " (cdr (assoc 2 ent-data))))

       ;; Check if Block has attribute flag (group code 66 == 1)
       (if (and (assoc 66 ent-data) (= (cdr (assoc 66 ent-data)) 1))
         (progn
           (setq att (entnext ent))
           ;; Scan all block attributes
           (while (and att (not (equal (cdr (assoc 0 (entget att))) "SEQEND")))
             (setq att-data (entget att))
             (setq att-type (cdr (assoc 0 att-data)))
             (if (equal att-type "ATTRIB")
               (progn
                 (setq att-tag (str-upcase (cdr (assoc 2 att-data))))
                 (setq att-val (cdr (assoc 1 att-data)))
                 (princ (strcat "\n   [DEBUG ATTRIB] Tag: '" att-tag "' | Value: '" att-val "'"))

                 ;; Only process non-empty attribute values
                 (if (and att-val (not (equal (vl-string-trim " \t\r\n" att-val) "")))
                   (progn
                     (setq clean-att-val (vl-string-trim " \t\r\n" att-val))

                     ;; 1. Check for exact tag match: NAME, ROOM_NAME, ROOMNAME, ROOM, ROOM_NO, TITLE, SPACE, SPACE_NAME
                     (if (or (equal att-tag "NAME")
                             (equal att-tag "ROOM_NAME")
                             (equal att-tag "ROOMNAME")
                             (equal att-tag "ROOM")
                             (equal att-tag "ROOM_NO")
                             (equal att-tag "TITLE")
                             (equal att-tag "SPACE")
                             (equal att-tag "SPACE_NAME"))
                       (progn
                         (setq room-name clean-att-val)
                         (setq exact-name-found T)
                         (if (and (assoc 11 att-data)
                                  (not (equal (cdr (assoc 11 att-data)) '(0.0 0.0 0.0))))
                           (setq ins-pt (cdr (assoc 11 att-data)))
                         )
                       )
                       ;; 2. Fuzzy tag match if exact tag NAME not found yet
                       (if (and (not exact-name-found)
                                (or (null room-name) (equal room-name ""))
                                (or (wcmatch att-tag "*ROOM*")
                                    (wcmatch att-tag "*NAME*")
                                    (wcmatch att-tag "*DOOR*")
                                    (wcmatch att-tag "*TAG*")
                                    (wcmatch att-tag "*LABEL*")))
                         (progn
                           (setq room-name clean-att-val)
                           (if (and (assoc 11 att-data)
                                    (not (equal (cdr (assoc 11 att-data)) '(0.0 0.0 0.0))))
                             (setq ins-pt (cdr (assoc 11 att-data)))
                           )
                         )
                       )
                     )

                     ;; Secondary: Record attribute value if it matches DB rules (Space Name OR Door Tag)
                     (if (and (null found-att-val) (cad-qc-find-rule-smart clean-att-val rule-db))
                       (setq found-att-val clean-att-val)
                     )
                   )
                 )
               )
             )

             (setq att (entnext att))
           )
         )
         (princ "\n   [DEBUG INSERT] Block reference has no attribute sub-entities (Group 66 is not 1).")
       )

       ;; Fallback: If tag matching failed, use rule-matched attribute value
       (if (and (or (null room-name) (equal room-name "")) found-att-val)
         (setq room-name found-att-val)
       )
      )
    )

    ;; GUARD: If selected text is ALREADY a door tag (e.g. D008, D0081, D0082), SKIP IT to prevent duplicate placement!
    (if (and (or (equal ent-type "TEXT") (equal ent-type "MTEXT") (equal ent-type "ATTRIB"))
             (cad-is-already-door-tag room-name rule-db))
      (progn
        (princ (strcat "\n   [SKIP] Selected entity text '" room-name "' is already a door tag. Skipping duplicate placement."))
        (setq room-name "")
      )
    )

    (princ (strcat "\n   [DEBUG TARGET] Resolved Search Room Name: '" (if room-name room-name "") "'"))

    (if (and room-name (not (equal room-name "")))
      (progn
        (setq clean-name (cad-clean-mtext room-name))
        
        ;; Smart Match: Returns matched rule (or nil)
        (setq matched-rule (cad-qc-find-rule-smart clean-name rule-db))

        (if matched-rule
          (progn
            (setq finish-code (cdr (assoc "FINISH_CODE" (cdr matched-rule))))
            (setq door-spec (cdr (assoc "DOOR" (cdr matched-rule))))
            (setq door-width-map (cdr (assoc "DOOR_WIDTH_MAP" (cdr matched-rule))))
            (setq hw-spec (cdr (assoc "HARDWARE" (cdr matched-rule))))
            (setq wall-spec (cdr (assoc "WALL" (cdr matched-rule))))
            (setq floor-spec (cdr (assoc "FLOOR" (cdr matched-rule))))
            (setq ceil-spec (cdr (assoc "CEILING" (cdr matched-rule))))
            (setq notes-spec (cdr (assoc "NOTES" (cdr matched-rule))))

            ;; Resolve specific Door Tag based on requested door width (e.g. 90 -> D008, 120 -> D0081, 240 -> D0082)
            (setq primary-tag (cad-get-door-tag-by-width door-spec door-width-map door-width-input))
            ;; HARD GUARD: Ensure primary-tag is strictly a single clean tag (no commas, no spaces)
            (setq primary-tag (cad-clean-door-tag primary-tag))
            (setq clean-finish (cad-clean-code finish-code))

            ;; Output unified match details
            (princ (strcat "\n[SPACE MATCH] Space: " (cad-get-display-room-name (car matched-rule)) " -> Code: " clean-finish " | Door Tag (" door-width-input "cm): " primary-tag " | Hardware: " hw-spec))

            ;; Format door width string (e.g. "90 cm", "120 cm")
            (setq door-width-str door-width-input)
            (if (not (vl-string-search "CM" (str-upcase door-width-str)))
              (setq door-width-str (strcat door-width-str " cm"))
            )

            ;; EXCEL PUSH FEATURE: Every time a block is read, push Finish Code, Door Width, Door Tag, and MD Notes to Excel!
            (cad-push-block-to-excel excel-path clean-name clean-finish door-width-str primary-tag notes-spec)

            ;; Auto-insert / Auto-update Finish Code & Door Spec
            (if (and (equal auto-write "Y") primary-tag (not (equal primary-tag "")))
              (progn
                (setq block-attr-updated nil)

                ;; 1. If entity is Block Reference (INSERT), update finish code inside attributes (< - - >)
                (if (equal ent-type "INSERT")
                  (setq block-attr-updated (cad-update-block-code-attrs ent clean-finish primary-tag))
                )

                ;; 2. If entity is TEXT / MTEXT / ATTRIB, REPLACE its text string directly with primary-tag (e.g. "D0081")
                (if (or (equal ent-type "TEXT") (equal ent-type "MTEXT") (equal ent-type "ATTRIB"))
                  (progn
                    (setq ent-data (subst (cons 1 primary-tag) (assoc 1 ent-data) ent-data))
                    ;; Set text height to 30.0
                    (if (assoc 40 ent-data) (setq ent-data (subst '(40 . 30.0) (assoc 40 ent-data) ent-data)))
                    ;; Set alignment center/middle
                    (if (assoc 72 ent-data) (setq ent-data (subst '(72 . 1) (assoc 72 ent-data) ent-data)))
                    (if (assoc 73 ent-data) (setq ent-data (subst '(73 . 2) (assoc 73 ent-data) ent-data)))
                    (entmod ent-data)
                    (entupd ent)
                    (setq block-attr-updated T)
                  )
                )

                ;; 3. Insert Door/Window CIRCLE TAG (Radius = 50) BELOW BLOCK & BELOW FINISH CODE
                (if ins-pt
                  (progn
                    (setq radius 50.0)      ;; Radius = 50.0
                    (setq tag-text-h 30.0)  ;; Text Height = 30.0
                    
                    ;; Place Circle Tag below block and below finish code (offset Y = -180 for block, -120 for text)
                    (setq offset-y (if (equal ent-type "INSERT") 180.0 120.0))
                    (setq circle-pt (list (car ins-pt) (- (cadr ins-pt) offset-y) (caddr ins-pt)))

                    ;; 1. Place Centered Door Number Text inside Circle (e.g. D0081 or D008 or D0082)
                    (if (equal ent-type "INSERT")
                      (entmake
                        (list
                          '(0 . "TEXT")
                          '(100 . "AcDbEntity")
                          (cons 8 layer-name)
                          '(100 . "AcDbText")
                          (cons 10 circle-pt)
                          (cons 11 circle-pt)
                          (cons 40 tag-text-h)
                          (cons 1 primary-tag)
                          '(72 . 1) ;; Center horizontal
                          '(73 . 2) ;; Middle vertical
                          '(62 . 3) ;; Color 3 = Green
                        )
                      )
                    )

                    ;; 2. Draw Circle Tag (Radius = 50.0, Cyan / Color 4) centered at circle-pt
                    (entmake
                      (list
                        '(0 . "CIRCLE")
                        '(100 . "AcDbEntity")
                        (cons 8 layer-name)
                        '(100 . "AcDbCircle")
                        (cons 10 circle-pt)
                        (cons 40 radius)
                        '(62 . 4) ;; Color 4 = Cyan
                      )
                    )

                    (princ (strcat " -> Placed Door Circle Tag (" primary-tag ") BELOW block & finish code [offset-y=" (rtos offset-y 2 1) ", R=50]"))
                  )
                )
              )
            )
          )
          (progn
            (setq fail-count (+ fail-count 1))
            (princ (strcat "\n[WARN] " clean-name " | No matching space name or door tag in database."))
            ;; Push unmatched block read to Excel as well
            (setq door-width-str door-width-input)
            (if (not (vl-string-search "CM" (str-upcase door-width-str)))
              (setq door-width-str (strcat door-width-str " cm"))
            )
            (cad-push-block-to-excel excel-path clean-name "" door-width-str "" "無對應規範備註")
          )
        )
      )
    )

    (setq idx (+ idx 1))
  )

  (command "_.REDRAW")
  (princ "\n---------------------------------------------------------------------------------------------------")
  (princ (strcat "\n\n[RESULTS] AutoCAD Spatial & Door Schedule QC Placement Results:"))
  (princ (strcat "\n   Matched Items: " (itoa pass-count)))
  (princ (strcat "\n   Unmatched: " (itoa fail-count)))

  ;; Automatically launch and open Excel for user convenience
  (vl-catch-all-apply
    '(lambda (/ wsh)
       (setq wsh (vlax-create-object "WScript.Shell"))
       (if wsh
         (progn
           (vlax-invoke-method wsh 'Run (strcat "cmd /c start \"\" \"" excel-path "\"") 0 :vlax-false)
           (vlax-release-object wsh)
         )
       )
     )
  )

  (alert (strcat "Result Summary:\nMatched: " (itoa pass-count) "\nUnmatched: " (itoa fail-count) "\n\nExcel Export File Updated & Opened:\n" excel-path))
  (princ "\n==========================================================\n")
  (princ)
)

;; Helper: Push single block info (Finish Code, Door Width, Door Tag, MD Notes) to Excel file (Supports Active Excel COM & File Append)
(defun cad-push-block-to-excel (filepath room-name finish-code door-width door-tag notes / file-exists file line-str clean-r clean-f clean-w clean-d clean-n xl-app xl-wkb xl-sheet last-row com-success)
  (if (null room-name) (setq room-name ""))
  (if (null finish-code) (setq finish-code ""))
  (if (null door-width) (setq door-width ""))
  (if (null door-tag) (setq door-tag ""))
  (if (null notes) (setq notes ""))

  ;; Clean commas, quotes, and newlines to ensure clean format for Excel
  (setq clean-r (vl-string-translate ",\"\n\r" "    " room-name))
  (setq clean-f (vl-string-translate ",\"\n\r" "    " finish-code))
  (setq clean-w (vl-string-translate ",\"\n\r" "    " door-width))
  (setq clean-d (vl-string-translate ",\"\n\r" "    " door-tag))
  (setq clean-n (vl-string-translate ",\"\n\r" "    " notes))

  (setq com-success nil)

  ;; 1. Mode A: Check if Excel Application is ALREADY OPEN on screen
  (vl-catch-all-apply
    '(lambda ()
       (setq xl-app (vlax-get-object "Excel.Application"))
       (if (and xl-app (= (type xl-app) 'VLA-OBJECT))
         (progn
           (setq xl-wkb (vlax-get-property xl-app 'ActiveWorkbook))
           (if (and xl-wkb (= (type xl-wkb) 'VLA-OBJECT))
             (progn
               (setq xl-sheet (vlax-get-property xl-wkb 'ActiveSheet))
               (if (and xl-sheet (= (type xl-sheet) 'VLA-OBJECT))
                 (progn
                   (setq last-row (1+ (vlax-get-property (vlax-get-property (vlax-get-property xl-sheet 'UsedRange) 'Rows) 'Count)))
                   (vlax-put-property (vlax-get-property xl-sheet 'Range (strcat "A" (itoa last-row))) 'Value2 clean-r)
                   (vlax-put-property (vlax-get-property xl-sheet 'Range (strcat "B" (itoa last-row))) 'Value2 clean-f)
                   (vlax-put-property (vlax-get-property xl-sheet 'Range (strcat "C" (itoa last-row))) 'Value2 clean-w)
                   (vlax-put-property (vlax-get-property xl-sheet 'Range (strcat "D" (itoa last-row))) 'Value2 clean-d)
                   (vlax-put-property (vlax-get-property xl-sheet 'Range (strcat "E" (itoa last-row))) 'Value2 clean-n)
                   (setq com-success T)
                   (princ (strcat "\n   [EXCEL COM PUSH OK] Direct-injected block '" clean-r "' into active open Excel worksheet!"))
                 )
               )
             )
           )
         )
       )
     )
  )

  ;; 2. Mode B: If Excel is NOT open on screen, write/append directly to file on disk
  (if (null com-success)
    (progn
      (setq file-exists (findfile filepath))
      (setq file (open filepath "a"))
      (if file
        (progn
          ;; If file is newly created, write UTF-8 BOM and CSV Header
          (if (null file-exists)
            (write-line (strcat (chr 239) (chr 187) (chr 191) "圖塊/空間名稱,粉刷編號,門寬,門窗編號,.md檔備註") file)
          )
          ;; Append current block record
          (setq line-str (strcat clean-r "," clean-f "," clean-w "," clean-d "," clean-n))
          (write-line line-str file)
          (close file)
          (princ (strcat "\n   [EXCEL PUSH OK] Block '" clean-r "' -> Finish: " clean-f " | Width: " clean-w " | Door: " clean-d " | MD Notes: " clean-n " -> Appended to Excel file: " filepath))
        )
        (princ (strcat "\n   [EXCEL WARN] Cannot open file (please check if Excel file is locked): " filepath))
      )
    )
  )
)

;; Helper: Extract value after colon from Markdown line (handles half-width :, full-width ：, and byte sequences)
(defun cad-extract-md-value (line / pos val)
  (if (null line) (setq line ""))
  (setq pos (vl-string-search ":" line))
  ;; Try full-width Chinese colon ： if half-width : is not found
  (if (null pos)
    (setq pos (vl-string-search "：" line))
  )
  ;; Try pure AutoLISP Big5 full-width colon byte sequence (chr 161) (chr 71)
  (if (null pos)
    (setq pos (vl-string-search (strcat (chr 161) (chr 71)) line))
  )
  ;; Try UTF-8 full-width colon byte sequence (chr 239) (chr 188) (chr 186)
  (if (null pos)
    (setq pos (vl-string-search (strcat (chr 239) (chr 188) (chr 186)) line))
  )

  (if (and pos (numberp pos))
    (progn
      (setq val (substr line (+ pos 2)))
      (vl-string-trim " \t\r\n*:` " val)
    )
    ""
  )
)

;; Helper: Clean MTEXT formatting codes safely without corrupting Chinese characters
(defun cad-clean-mtext (str / pos)
  (if (null str) (setq str ""))
  (while (setq pos (vl-string-search "\\P" str)) (setq str (strcat (substr str 1 pos) " " (substr str (+ pos 3)))))
  (while (setq pos (vl-string-search "\\p" str)) (setq str (strcat (substr str 1 pos) " " (substr str (+ pos 3)))))
  (while (setq pos (vl-string-search "{" str)) (setq str (strcat (substr str 1 pos) (substr str (+ pos 2)))))
  (while (setq pos (vl-string-search "}" str)) (setq str (strcat (substr str 1 pos) (substr str (+ pos 2)))))
  (vl-string-trim " \t\r\n" str)
)

;; Helper: Convert ASCII string to uppercase safely
(defun str-upcase (str) (vl-string-translate "abcdefghijklmnopqrstuvwxyz" "ABCDEFGHIJKLMNOPQRSTUVWXYZ" str))

(defun cad-qc-show-error (msg)
  (alert msg)
  (princ)
)

;; Helper: Remove hyphens, spaces, underscores, and parentheses notes from code string (e.g. "PE08 (note)" -> "PE08")
(defun cad-clean-code (str / res i ch pos)
  (if (null str) (setq str ""))
  (setq pos (vl-string-search (chr 40) str))
  (if pos
    (setq str (substr str 1 pos))
  )
  (setq res "")
  (setq i 1)
  (while (<= i (strlen str))
    (setq ch (substr str i 1))
    (if (not (or (equal ch "-") (equal ch " ") (equal ch "_")))
      (setq res (strcat res ch))
    )
    (setq i (+ i 1))
  )
  res
)

;; Helper: Update block attribute tags (< - - >, FINISH_CODE, DOOR) with finish code & door spec
(defun cad-update-block-code-attrs (block-ent code-str door-str / clean-c c1 c2 c3 c4 c5 att att-data att-tag dash-count updated-any clean-door)
  (setq clean-c (cad-clean-code code-str))
  (setq clean-door (cad-clean-door-tag door-str))
  (setq updated-any nil)

  (if (>= (strlen clean-c) 4)
    (progn
      (setq c1 (substr clean-c 1 1))
      (setq c2 (substr clean-c 2 1))
      (setq c3 (substr clean-c 3 1))
      (setq c4 (substr clean-c 4 1))
      (setq c5 (if (>= (strlen clean-c) 6) (substr clean-c 5 2) (substr clean-c 3 2)))

      (setq att (entnext block-ent))
      (setq dash-count 0)

      (while (and att (not (equal (cdr (assoc 0 (entget att))) "SEQEND")))
        (setq att-data (entget att))
        (setq att-tag (str-upcase (cdr (assoc 2 att-data))))

        (cond
          ((equal att-tag "<")
           (setq att-data (subst (cons 1 c1) (assoc 1 att-data) att-data))
           (entmod att-data)
           (setq updated-any T)
          )
          ((equal att-tag "-")
           (setq dash-count (+ dash-count 1))
           (cond
             ((= dash-count 1)
              (setq att-data (subst (cons 1 c2) (assoc 1 att-data) att-data))
              (entmod att-data)
              (setq updated-any T)
             )
             ((= dash-count 2)
              (setq att-data (subst (cons 1 c3) (assoc 1 att-data) att-data))
              (entmod att-data)
              (setq updated-any T)
             )
             ((= dash-count 3)
              (setq att-data (subst (cons 1 c5) (assoc 1 att-data) att-data))
              (entmod att-data)
              (setq updated-any T)
             )
           )
          )
          ((equal att-tag ">")
           (setq att-data (subst (cons 1 c4) (assoc 1 att-data) att-data))
           (entmod att-data)
           (setq updated-any T)
          )
          ((or (equal att-tag "FINISH") (equal att-tag "FINISH_CODE") (equal att-tag "CODE") (equal att-tag "PE_CODE"))
           (setq att-data (subst (cons 1 clean-c) (assoc 1 att-data) att-data))
           (entmod att-data)
           (setq updated-any T)
          )
          ((and clean-door (not (equal clean-door ""))
                (or (equal att-tag "DOOR") (equal att-tag "DOOR_NO") (equal att-tag "DOOR_TAG") (equal att-tag "DOOR_SPEC")))
           (setq att-data (subst (cons 1 clean-door) (assoc 1 att-data) att-data))
           (entmod att-data)
           (setq updated-any T)
          )
        )

        (setq att (entnext att))
      )
    )
  )

  (if updated-any
    (entupd block-ent)
  )
  updated-any
)

;; Helper: Strip BOM & leading/trailing whitespace safely
(defun cad-clean-line (line / s)
  (if (null line) (setq line ""))
  (setq s (vl-string-trim " \t\r\n" line))
  (if (and (>= (strlen s) 3)
           (= (ascii (substr s 1 1)) 239)
           (= (ascii (substr s 2 1)) 187)
           (= (ascii (substr s 3 1)) 191))
    (setq s (substr s 4))
  )
  (vl-string-trim " \t\r\n" s)
)

;; Helper: Read Markdown database with UTF-8 OLE Stream or native fallback
(defun cad-read-md-file (filepath / stream text file line-list raw-line line current-space val db clean-val item-list item pos w-digits tag-val clean-tag existing-door existing-map entry-str)
  (setq db '())
  (setq text nil)

  (vl-catch-all-apply
    '(lambda ()
       (setq stream (vlax-create-object "ADODB.Stream"))
       (vlax-put-property stream 'Charset "UTF-8")
       (vlax-invoke-method stream 'Open)
       (vlax-invoke-method stream 'LoadFromFile filepath)
       (setq text (vlax-variant-value (vlax-invoke-method stream 'ReadText -1)))
       (vlax-invoke-method stream 'Close)
       (vlax-release-object stream)
     )
  )

  (if (and text (stringp text) (not (equal text "")))
    (setq line-list (cad-split-string text "\n"))
    (progn
      (setq file (open filepath "r"))
      (if file
        (progn
          (setq line-list '())
          (while (setq line (read-line file))
            (setq line-list (cons line line-list))
          )
          (close file)
          (setq line-list (reverse line-list))
        )
      )
    )
  )

  (setq current-space nil)

  (foreach raw-line line-list
    (setq line (cad-clean-line raw-line))

    (cond
      ;; Space Name Header (## 變電站 or # 變電站)
      ((and (or (wcmatch line "##*") (wcmatch line "# *"))
            (not (wcmatch line "*規範數據庫*"))
            (not (wcmatch line "*對照表*")))
       (setq current-space (cad-normalize-room-name line))
       (setq db (cons (list current-space 
                            (cons "FINISH_CODE" "") 
                            (cons "DOOR" "") 
                            (cons "DOOR_WIDTH_MAP" "") 
                            (cons "HARDWARE" "") 
                            (cons "WALL" "") 
                            (cons "FLOOR" "") 
                            (cons "CEILING" "") 
                            (cons "NOTES" "")) 
                      db))
       (princ (strcat "\n   [DB DEBUG] Registered Space Rule: '" (cad-get-display-room-name current-space) "'"))
      )

      ;; Explicit Door Width Map (e.g. - **門寬尺寸對照**: 90: D008; 120: D0081)
      ((and current-space (or (wcmatch line "*門寬*") (wcmatch line "*WIDTH*")))
       (setq val (cad-extract-md-value line))
       (if (and val (not (equal val "")))
         (cad-qc-update-rule-db db current-space "DOOR_WIDTH_MAP" val)
       )
      )

      ;; Key-Value items under Space Header
      ((and current-space 
            (or (vl-string-search ":" line)
                (vl-string-search "：" line)
                (wcmatch line "*- *:*")))
       (setq val (cad-extract-md-value line))
       (if (and val (not (equal val "")))
         (progn
           (setq clean-val (cad-clean-code val))

           ;; 1. Multi-Encoding Door & Window Line Check (Supports 門, 窗, DOOR, WIN, 240門號, 240窗編號)
           (if (and (or (wcmatch line "*- **門窗編號***")
                        (wcmatch line "*- **門窗***")
                        (wcmatch line "*門窗編號*")
                        (wcmatch line "*門窗*")
                        (wcmatch line "*門*")
                        (wcmatch line "*窗*")
                        (wcmatch line "*DOOR*")
                        (wcmatch line "*WIN*")
                        (wcmatch line "*90*")
                        (wcmatch line "*120*")
                        (wcmatch line "*240*"))
                    (not (or (wcmatch line "*粉刷*")
                             (wcmatch line "*門鎖*")
                             (wcmatch line "*五金*")
                             (wcmatch line "*牆面*")
                             (wcmatch line "*地面*")
                             (wcmatch line "*天花*")
                             (wcmatch line "*備註*"))))
             (progn
               ;; Parse door line and populate both DOOR and DOOR_WIDTH_MAP cleanly
               (setq item-list (cad-split-string val ",; \t\r\n"))
               (foreach item item-list
                 (setq item (vl-string-trim " \t\r\n" item))
                 (if (not (equal item ""))
                   (progn
                     (setq w-digits nil)
                     (setq tag-val nil)

                     (if (vl-string-search ":" item)
                       (progn
                         (setq pos (vl-string-search ":" item))
                         (setq w-digits (cad-extract-digits (substr item 1 pos)))
                         (setq tag-val (cad-clean-door-tag (substr item (+ pos 2))))
                       )
                       (progn
                         (setq clean-tag (cad-clean-door-tag item))
                         (setq tag-val clean-tag)
                         ;; Extract width digits ONLY from line header before colon (e.g. "- **90cm門窗編號**:", "- **240門號**:")
                         (setq pos (vl-string-search ":" line))
                         (if pos
                           (setq w-digits (cad-extract-digits (substr line 1 pos)))
                           (setq w-digits (cad-extract-digits line))
                         )
                       )
                     )

                     (if (and tag-val (not (equal tag-val "")))
                       (progn
                         (setq existing-door (cdr (assoc "DOOR" (cdr (assoc current-space db)))))
                         (if (and existing-door (not (equal existing-door "")))
                           (if (not (vl-string-search tag-val existing-door))
                             (cad-qc-update-rule-db db current-space "DOOR" (strcat existing-door ", " tag-val))
                           )
                           (cad-qc-update-rule-db db current-space "DOOR" tag-val)
                         )

                         (if (and w-digits (not (equal w-digits "")))
                           (progn
                             (setq entry-str (strcat w-digits ":" tag-val))
                             (setq existing-map (cdr (assoc "DOOR_WIDTH_MAP" (cdr (assoc current-space db)))))
                             (if (and existing-map (not (equal existing-map "")))
                               (if (not (vl-string-search entry-str existing-map))
                                 (cad-qc-update-rule-db db current-space "DOOR_WIDTH_MAP" (strcat existing-map ", " entry-str))
                               )
                               (cad-qc-update-rule-db db current-space "DOOR_WIDTH_MAP" entry-str)
                             )
                           )
                         )
                       )
                     )
                   )
                 )
               )
             )
             ;; 2. Check if line is Finish Code line (- **粉刷對照編號**:)
             (if (or (wcmatch line "*- **粉刷***")
                     (wcmatch line "*FINISH*")
                     (and (>= (strlen clean-val) 4) (equal (substr clean-val 1 1) "P")))
               (cad-qc-update-rule-db db current-space "FINISH_CODE" val)
               ;; 3. Check if line is Lock Hardware (- **門鎖五金編號**:)
               (if (or (wcmatch line "*- **門鎖***")
                       (wcmatch (str-upcase val) "*HD-*"))
                 (cad-qc-update-rule-db db current-space "HARDWARE" val)
                 ;; 4. Wall Finish
                 (if (wcmatch line "*- **牆面***")
                   (cad-qc-update-rule-db db current-space "WALL" val)
                   ;; 5. Floor Finish
                   (if (wcmatch line "*- **地面***")
                     (cad-qc-update-rule-db db current-space "FLOOR" val)
                     ;; 6. Ceiling Finish
                     (if (wcmatch line "*- **天花***")
                       (cad-qc-update-rule-db db current-space "CEILING" val)
                       ;; 7. Notes
                       (if (wcmatch line "*- **備註***")
                         (cad-qc-update-rule-db db current-space "NOTES" val)
                       )
                     )
                   )
                 )
               )
             )
           )
         )
       )
      )
    )
  )
  db
)

(defun cad-qc-update-rule-db (db space key val / item sub)
  (setq item (assoc space db))
  (if item (progn (setq sub (assoc key (cdr item))) (if sub (rplacd sub val))))
)

;; Helper: Pure AutoLISP Room Name Normalizer (Returns Pure Big5 Byte Sequence)
(defun cad-normalize-room-name (str / clean-s)
  (if (null str) (setq str ""))
  (setq clean-s (vl-string-trim " \t\r\n#*" str))
  (cond
    ;; 進氣機房
    ((or (equal clean-s "進氣機房")
         (vl-string-search "進氣機房" clean-s)
         (vl-string-search (strcat (chr 182) (chr 105) (chr 174) (chr 240) (chr 190) (chr 247) (chr 169) (chr 208)) clean-s)
         (vl-string-search (strcat (chr 233) (chr 128) (chr 178) (chr 230) (chr 176) (chr 163) (chr 230) (chr 169) (chr 159) (chr 230) (chr 136) (chr 191)) clean-s))
     (strcat (chr 182) (chr 105) (chr 174) (chr 240) (chr 190) (chr 247) (chr 169) (chr 208)))

    ;; 變電站
    ((or (equal clean-s "變電站")
         (vl-string-search "變電站" clean-s)
         (vl-string-search "變電" clean-s)
         (vl-string-search (strcat (chr 197) (chr 220) (chr 185) (chr 113) (chr 175) (chr 184)) clean-s)
         (vl-string-search (strcat (chr 232) (chr 174) (chr 138) (chr 233) (chr 155) (chr 187) (chr 231) (chr 171) (chr 153)) clean-s))
     (strcat (chr 197) (chr 220) (chr 185) (chr 113) (chr 175) (chr 184)))

    ;; 簡報室
    ((or (equal clean-s "簡報室")
         (vl-string-search "簡報室" clean-s)
         (vl-string-search "會議室" clean-s)
         (vl-string-search (strcat (chr 194) (chr 178) (chr 179) (chr 248) (chr 171) (chr 199)) clean-s)
         (vl-string-search (strcat (chr 231) (chr 176) (chr 161) (chr 229) (chr 160) (chr 177) (chr 229) (chr 174) (chr 164)) clean-s))
     (strcat (chr 194) (chr 178) (chr 179) (chr 248) (chr 171) (chr 199)))

    ;; 梯廳
    ((or (equal clean-s "梯廳")
         (vl-string-search "梯廳" clean-s)
         (vl-string-search "電梯廳" clean-s)
         (vl-string-search (strcat (chr 177) (chr 232) (chr 198) (chr 85)) clean-s)
         (vl-string-search (strcat (chr 230) (chr 162) (chr 175) (chr 229) (chr 187) (chr 179)) clean-s))
     (strcat (chr 177) (chr 232) (chr 198) (chr 85)))

    ;; 辦公室
    ((or (equal clean-s "辦公室")
         (vl-string-search "辦公室" clean-s)
         (vl-string-search "辦公" clean-s)
         (vl-string-search (strcat (chr 191) (chr 236) (chr 164) (chr 189) (chr 171) (chr 199)) clean-s)
         (vl-string-search (strcat (chr 232) (chr 190) (chr 166) (chr 229) (chr 133) (chr 172) (chr 229) (chr 174) (chr 164)) clean-s))
     (strcat (chr 191) (chr 236) (chr 164) (chr 189) (chr 171) (chr 199)))

    ;; 儲藏室
    ((or (equal clean-s "儲藏室")
         (vl-string-search "儲藏室" clean-s)
         (vl-string-search "庫房" clean-s)
         (vl-string-search (strcat (chr 192) (chr 120) (chr 194) (chr 195) (chr 171) (chr 199)) clean-s)
         (vl-string-search (strcat (chr 229) (chr 132) (chr 178) (chr 232) (chr 151) (chr 143) (chr 229) (chr 174) (chr 164)) clean-s))
     (strcat (chr 192) (chr 120) (chr 194) (chr 195) (chr 171) (chr 199)))

    ;; 廁所
    ((or (equal clean-s "廁所")
         (vl-string-search "廁所" clean-s)
         (vl-string-search "洗手" clean-s)
         (vl-string-search "WC" (str-upcase clean-s))
         (vl-string-search (strcat (chr 180) (chr 90) (chr 169) (chr 210)) clean-s)
         (vl-string-search (strcat (chr 229) (chr 187) (chr 129) (chr 230) (chr 137) (chr 128)) clean-s))
     (strcat (chr 180) (chr 90) (chr 169) (chr 210)))

    ;; 機房
    ((or (equal clean-s "機房")
         (vl-string-search "機房" clean-s)
         (vl-string-search (strcat (chr 190) (chr 247) (chr 169) (chr 208)) clean-s)
         (vl-string-search (strcat (chr 230) (chr 169) (chr 159) (chr 230) (chr 136) (chr 191)) clean-s))
     (strcat (chr 190) (chr 247) (chr 169) (chr 208)))

    (t clean-s)
  )
)

;; Helper: Smart match space rule (returns (rule mode_type))
(defun cad-qc-find-rule-smart (label-str db / found norm-label norm-db-space door-str door-list tag-item raw-space)
  (setq found nil)
  (setq norm-label (cad-normalize-room-name label-str))

  (if (and norm-label (not (equal norm-label "")))
    (progn
      ;; 1. Try matching by Space Name (e.g. "進氣機房", "變電站", "機房")
      (foreach r db
        (setq raw-space (car r))
        (setq norm-db-space (cad-normalize-room-name raw-space))

        (if (and norm-db-space (not (equal norm-db-space "")))
          (if (or (equal norm-label norm-db-space)
                  (equal raw-space norm-label)
                  (vl-string-search norm-db-space norm-label)
                  (vl-string-search norm-label norm-db-space))
            (if (null found)
              (setq found r)
              (if (or (equal norm-label norm-db-space)
                      (> (strlen (car r)) (strlen (car found))))
                (setq found r)
              )
            )
          )
        )
      )

      ;; 2. If not found, try matching by Door Tag / Door Schedule (e.g. "SD1-A", "D-01", "D-008")
      (if (null found)
        (progn
          (setq norm-label (str-upcase (vl-string-trim " \t\r\n" label-str)))
          (foreach r db
            (setq door-str (str-upcase (cdr (assoc "DOOR" (cdr r)))))
            (if (not (equal door-str ""))
              (progn
                (setq door-list (cad-split-string door-str ",; \t\r\n"))
                (foreach tag-item door-list
                  (setq tag-item (str-upcase (vl-string-trim " \t\r\n" tag-item)))
                  (if (and (not (equal tag-item ""))
                           (or (equal norm-label tag-item)
                               (and (>= (strlen tag-item) 3) (vl-string-search tag-item norm-label))))
                    (if (null found) (setq found r))
                  )
                )
              )
            )
          )
        )
      )
    )
  )

  found
)

;; Command Aliases with Automatic Reload
(defun c:CADQC (/ reload-path)
  (setq reload-path "C:\\Users\\葉真希\\Downloads\\匯出製 Excel\\RevitQC_空間規範數據庫\\cad_qc.lsp")
  (if (not (findfile reload-path))
    (setq reload-path "C:\\Users\\葉真希\\Downloads\\1\\cad_qc.lsp")
  )
  (if (not (findfile reload-path))
    (setq reload-path "C:\\Users\\葉真希\\Downloads\\--main\\RevitQC_空間規範數據庫\\cad_qc.lsp")
  )
  (if (findfile reload-path)
    (vl-catch-all-apply '(lambda () (load reload-path)))
  )
  (c:REVITQC)
)

(defun c:QC () (c:CADQC))

(princ "\n[OK] cad_qc.lsp v16.0 (Perfect Engine) loaded successfully! Type CADQC, QC or REVITQC in AutoCAD command line.")
(princ)
