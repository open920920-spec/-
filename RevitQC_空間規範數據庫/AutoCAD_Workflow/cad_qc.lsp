;; ==============================================================================
;; AutoCAD Spatial & Door Schedule Quality Control Tool (cad_qc.lsp)
;; 
;; Dual Mode Engine:
;;   - MODE A (Space Name): Selecting "變電站" or "機房" writes PE-01 / PE-02 underneath.
;;   - MODE B (Door Tag / Door Schedule): Selecting "SD1-A", "D-01", "D-02", "SD2-B", "D-05", "FD1-A" 
;;     automatically reverse-matches space "變電站", outputs PE-01, HD-01 & specs.
;;
;; Commands: CADQC, QC, REVITQC
;; ==============================================================================

(vl-load-com)

;; --- Main Command ---
(defun c:REVITQC (/ filepath file line current-space val ss idx total ent ent-data ent-type room-name clean-name matched-rule finish-code door-spec hw-spec wall-spec floor-spec ceil-spec notes-spec pass-count fail-count att att-tag att-val clean-att-val exact-name-found found-att-val auto-write ins-pt text-h layer-name new-y new-pt align-h align-v new-ent block-attr-updated offset-h new-y2 new-pt2 rule-db)
  (princ "\n==========================================================")
  (princ "\n Spatial & Door Schedule QC Tool (AutoCAD DWG Scanner)")
  (princ "\n==========================================================")

  ;; Try to locate the Markdown rule file in current DWG directory
  (setq filepath (strcat (getvar "DWGPREFIX") "空間裝修與門窗對照表.md"))
  (if (not (findfile filepath))
    (setq filepath (getfiled "Select Spatial & Door Regulation File" "" "md;txt;*" 4))
  )

  (if (or (null filepath) (not (findfile filepath)))
    (progn
      (cad-qc-show-error "Error: Spatial Regulation Database file not found. Please select a .md file.")
      (exit)
    )
  )

  (princ (strcat "\n[DB] Reading Database File: " filepath))

  ;; Parse Markdown Database (Supports UTF-8 ADODB.Stream & Native ANSI)
  (setq rule-db (cad-read-md-file filepath))

  (princ (strcat "\n[OK] Loaded " (itoa (length rule-db)) " space rules & door schedules from database."))

  ;; Prompt user for auto text insertion below space name / door tag
  (initget "Y N")
  (setq auto-write (getkword "\nAuto-insert Finish Code and Door/Window Number (e.g. PE-01, D-01) below Space Name / Door Tag? [Yes(Y)/No(N)] <Y>: "))
  (if (null auto-write) (setq auto-write "Y"))

  ;; --- Select DWG Entities (Supports Space Names, Door Schedule Tables, Door Tags) ---
  (princ "\n\nSelect DWG Room Labels or Door Schedule Tags (TEXT, MTEXT, ATTRIB, INSERT):")
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
  (princ "\nMode | DWG Label / Tag | Matched Space | Finish Code | Hardware | Wall / Floor / Ceiling Specs")
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
            (setq hw-spec (cdr (assoc "HARDWARE" (cdr matched-rule))))
            (setq wall-spec (cdr (assoc "WALL" (cdr matched-rule))))
            (setq floor-spec (cdr (assoc "FLOOR" (cdr matched-rule))))
            (setq ceil-spec (cdr (assoc "CEILING" (cdr matched-rule))))
            (setq notes-spec (cdr (assoc "NOTES" (cdr matched-rule))))
            (setq pass-count (+ pass-count 1))

            ;; Output unified match details (treat all as space name)
            (princ (strcat "\n[SPACE MATCH] Space: " (car matched-rule) " -> Code: " finish-code " | Hardware: " hw-spec " | Doors: " door-spec))

            ;; Auto-insert / Auto-update Finish Code & Door Spec
            (if (and (equal auto-write "Y") finish-code (not (equal finish-code "")))
              (progn
                (setq block-attr-updated nil)
                (if (equal ent-type "INSERT")
                  (setq block-attr-updated (cad-update-block-code-attrs ent finish-code door-spec))
                )

                (if block-attr-updated
                  (princ (strcat " -> Auto-updated Block Attributes < - - > with (" finish-code ")"))
                  ;; Fallback: Place TEXT below at (X, Y - 1.6*H)
                  (if ins-pt
                    (progn
                      (setq new-y (- (cadr ins-pt) (* 1.6 text-h)))
                      (setq new-pt (list (car ins-pt) new-y (caddr ins-pt)))

                      (setq new-ent
                        (entmake
                          (list
                            '(0 . "TEXT")
                            '(100 . "AcDbEntity")
                            (cons 8 layer-name)
                            '(100 . "AcDbText")
                            (cons 10 new-pt)
                            (cons 11 new-pt)
                            (cons 40 text-h)
                            (cons 1 finish-code)
                            (cons 72 align-h)
                            (cons 73 align-v)
                            '(62 . 3) ;; Color 3 = Green
                          )
                        )
                      )
                      (princ (strcat " -> Auto-placed TEXT (" finish-code ") below at Y=" (rtos new-y 2 2)))
                    )
                  )
                )

                ;; Insert Door/Window number below if present
                (if (and door-spec (not (equal door-spec "")) ins-pt)
                  (progn
                    (setq offset-h (if block-attr-updated 1.6 3.2))
                    (setq new-y2 (- (cadr ins-pt) (* offset-h text-h)))
                    (setq new-pt2 (list (car ins-pt) new-y2 (caddr ins-pt)))
                    (entmake
                      (list
                        '(0 . "TEXT")
                        '(100 . "AcDbEntity")
                        (cons 8 layer-name)
                        '(100 . "AcDbText")
                        (cons 10 new-pt2)
                        (cons 11 new-pt2)
                        (cons 40 text-h)
                        (cons 1 door-spec)
                        (cons 72 align-h)
                        (cons 73 align-v)
                        '(62 . 5) ;; Color 5 = Blue for door spec
                      )
                    )
                    (princ (strcat " -> Auto-placed TEXT (" door-spec ") below at Y=" (rtos new-y2 2 2)))
                  )
                )
              )
            )
          )
          (progn
            (setq fail-count (+ fail-count 1))
            (princ (strcat "\n[WARN] " clean-name " | No matching space name or door tag in database."))
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
  (alert (strcat "Result Summary:\nMatched: " (itoa pass-count) "\nUnmatched: " (itoa fail-count)))
  (princ "\n==========================================================\n")
  (princ)
)

;; Helper: Extract value after colon from Markdown line (handles half-width :, full-width ：, and checks numberp)
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

;; Helper: Clean MTEXT formatting codes like {\f...;}, \P, \A1;, \H...;, {}
(defun cad-clean-mtext (str / pos endpos)
  (if (null str) (setq str ""))
  (while (setq pos (vl-string-search "\\P" str)) (setq str (strcat (substr str 1 pos) " " (substr str (+ pos 3)))))
  (while (setq pos (vl-string-search "\\p" str)) (setq str (strcat (substr str 1 pos) " " (substr str (+ pos 3)))))
  (while (setq pos (vl-string-search "{" str)) (setq str (strcat (substr str 1 pos) (substr str (+ pos 2)))))
  (while (setq pos (vl-string-search "}" str)) (setq str (strcat (substr str 1 pos) (substr str (+ pos 2)))))
  
  ;; Strip \f...; and \A...; and \H...; formatting prefixes
  (while (and (setq pos (vl-string-search "\\" str)) (setq endpos (vl-string-search ";" str)) (> endpos pos))
    (setq str (strcat (substr str 1 pos) (substr str (+ endpos 2))))
  )
  (vl-string-trim " \t\r\n" str)
)

;; Helper: Convert string to uppercase
(defun str-upcase (str) (vl-string-translate "abcdefghijklmnopqrstuvwxyz" "ABCDEFGHIJKLMNOPQRSTUVWXYZ" str))

;; Helper: Update rule-db item
(defun cad-qc-update-rule (space key val / item sub)
  (setq item (assoc space rule-db))
  (if item (progn (setq sub (assoc key (cdr item))) (if sub (rplacd sub val))))
)
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

;; Helper: Update block attribute tags (< - - >, FINISH_CODE, DOOR) with 4 characters of finish code & door spec
(defun cad-update-block-code-attrs (block-ent code-str door-str / clean-c c1 c2 c3 c4 att att-data att-tag dash-count updated-any)
  (setq clean-c (cad-clean-code code-str))
  (setq updated-any nil)

  (if (>= (strlen clean-c) 4)
    (progn
      (setq c1 (substr clean-c 1 1))
      (setq c2 (substr clean-c 2 1))
      (setq c3 (substr clean-c 3 1))
      (setq c4 (substr clean-c 4 1))

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
           (if (= dash-count 1)
             (progn
               (setq att-data (subst (cons 1 c2) (assoc 1 att-data) att-data))
               (entmod att-data)
               (setq updated-any T)
             )
             (if (= dash-count 2)
               (progn
                 (setq att-data (subst (cons 1 c3) (assoc 1 att-data) att-data))
                 (entmod att-data)
                 (setq updated-any T)
               )
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
          ((and door-str (not (equal door-str ""))
                (or (equal att-tag "DOOR") (equal att-tag "DOOR_NO") (equal att-tag "DOOR_TAG") (equal att-tag "DOOR_SPEC")))
           (setq att-data (subst (cons 1 door-str) (assoc 1 att-data) att-data))
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
;; Helper: Split string by delimiter
(defun cad-split-string (str delim / pos res item)
  (setq res '())
  (if (and str (not (equal str "")))
    (progn
      (while (setq pos (vl-string-search delim str))
        (setq item (vl-string-trim " \t\r\n" (substr str 1 pos)))
        (if (not (equal item "")) (setq res (cons item res)))
        (setq str (substr str (+ pos (strlen delim) 1)))
      )
      (setq item (vl-string-trim " \t\r\n" str))
      (if (not (equal item "")) (setq res (cons item res)))
    )
  )
  (reverse res)
)

;; Helper: Strip BOM / leading non-printable junk before #, -, *
(defun cad-clean-line (line / ch)
  (if (null line) (setq line ""))
  (setq line (vl-string-trim " \t\r\n" line))
  (while (and (> (strlen line) 0)
              (setq ch (ascii (substr line 1 1)))
              (or (< ch 32)
                  (= ch 239)   ;; UTF-8 BOM byte 1 (0xEF)
                  (= ch 187)   ;; UTF-8 BOM byte 2 (0xBB)
                  (= ch 191)   ;; UTF-8 BOM byte 3 (0xBF)
                  (= ch 65279))) ;; Unicode BOM char \ufeff
    (setq line (substr line 2))
  )
  (vl-string-trim " \t\r\n" line)
)

;; Helper: Read Markdown database with UTF-8 OLE Stream (Windows ANSI conversion) or fallback
(defun cad-read-md-file (filepath / stream text file line-list raw-line line current-space val db item-idx clean-val code-candidate)
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
  (setq item-idx 0)

  (foreach raw-line line-list
    (setq line (cad-clean-line raw-line))

    (cond
      ;; Space Name Header (## 變電站 or # 變電站)
      ((and (or (wcmatch line "##*") (wcmatch line "# *"))
            (not (wcmatch line "*規範數據庫*"))
            (not (wcmatch line "*對照表*")))
       (setq current-space (vl-string-trim " \t#*" line))
       (setq db (cons (list current-space 
                            (cons "FINISH_CODE" "") 
                            (cons "DOOR" "") 
                            (cons "HARDWARE" "") 
                            (cons "WALL" "") 
                            (cons "FLOOR" "") 
                            (cons "CEILING" "") 
                            (cons "NOTES" "")) 
                      db))
       (princ (strcat "\n   [DB DEBUG] Registered Space Rule: '" current-space "'"))
       (setq item-idx 0)
      )
      ;; Key-Value items under Space Header (e.g. - **粉刷對照編號**: PE01)
      ((and current-space 
            (or (vl-string-search ":" line)
                (vl-string-search "：" line)
                (wcmatch line "*- *:*")
                (wcmatch line "*- `*`*:*")
                (wcmatch line "*- `*`*`*`*:*")))
       (setq val (cad-extract-md-value line))
       (if (and val (not (equal val "")))
         (progn
           (setq item-idx (+ item-idx 1))
           (setq clean-val (cad-clean-code val))

           ;; 1. Check if value matches Finish Code candidate (e.g. PE08, PE01, P102...)
           (if (and (>= (strlen clean-val) 4)
                    (equal (substr clean-val 1 1) "P"))
             (cad-qc-update-rule-db db current-space "FINISH_CODE" val)
             ;; 2. Check if value is Lock Hardware (e.g. HD-01)
             (if (wcmatch (str-upcase val) "*HD-*")
               (cad-qc-update-rule-db db current-space "HARDWARE" val)
               ;; 3. Check if value is Door Tag list (e.g. SD1-A, D-01, D01)
               (if (or (wcmatch (str-upcase val) "*SD*")
                       (wcmatch (str-upcase val) "*FD*")
                       (wcmatch (str-upcase val) "*D-*")
                       (wcmatch (str-upcase val) "*D0*")
                       (wcmatch (str-upcase val) "*D1*")
                       (wcmatch (str-upcase val) "*D2*"))
                 (cad-qc-update-rule-db db current-space "DOOR" val)
                 ;; 4. Positional Fallback (1st: Finish Code, 2nd: Door, 3rd: HW, 4th: Wall, 5th: Floor, 6th: Ceiling, 7th: Notes)
                 (cond
                   ((= item-idx 1) (cad-qc-update-rule-db db current-space "FINISH_CODE" val))
                   ((= item-idx 2) (cad-qc-update-rule-db db current-space "DOOR" val))
                   ((= item-idx 3) (cad-qc-update-rule-db db current-space "HARDWARE" val))
                   ((= item-idx 4) (cad-qc-update-rule-db db current-space "WALL" val))
                   ((= item-idx 5) (cad-qc-update-rule-db db current-space "FLOOR" val))
                   ((= item-idx 6) (cad-qc-update-rule-db db current-space "CEILING" val))
                   ((= item-idx 7) (cad-qc-update-rule-db db current-space "NOTES" val))
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

;; Helper: Transcode UTF-8 string to native Windows ANSI/Big5 string
(defun cad-utf8-to-ansi (utf8-str / stream text)
  (if (or (null utf8-str) (equal utf8-str ""))
    ""
    (progn
      (setq text utf8-str)
      (vl-catch-all-apply
        '(lambda ()
           (setq stream (vlax-create-object "ADODB.Stream"))
           (vlax-put-property stream 'Type 2)
           (vlax-put-property stream 'Charset "utf-8")
           (vlax-invoke-method stream 'Open)
           (vlax-invoke-method stream 'WriteText utf8-str)
           (vlax-put-property stream 'Position 0)
           (vlax-put-property stream 'Charset "big5")
           (setq text (vlax-variant-value (vlax-invoke-method stream 'ReadText -1)))
           (vlax-invoke-method stream 'Close)
           (vlax-release-object stream)
         )
      )
      text
    )
  )
)

;; Helper: Pure AutoLISP Room Name Normalizer (Zero OLE dependency & Zero Escape sequence errors)
(defun cad-normalize-room-name (str / clean-s)
  (if (null str) (setq str ""))
  (setq clean-s (vl-string-trim " \t\r\n#*" str))
  (cond
    ;; 進氣機房
    ((or (equal clean-s "進氣機房")
         (vl-string-search "進氣機房" clean-s)
         (vl-string-search (strcat (chr 182) (chr 105) (chr 174) (chr 240) (chr 190) (chr 247) (chr 169) (chr 208)) clean-s)
         (vl-string-search (strcat (chr 233) (chr 128) (chr 178) (chr 230) (chr 176) (chr 163) (chr 230) (chr 169) (chr 159) (chr 230) (chr 136) (chr 191)) clean-s))
     "進氣機房")

    ;; 變電站
    ((or (equal clean-s "變電站")
         (vl-string-search "變電站" clean-s)
         (vl-string-search (strcat (chr 197) (chr 220) (chr 185) (chr 113) (chr 175) (chr 184)) clean-s)
         (vl-string-search (strcat (chr 232) (chr 174) (chr 138) (chr 233) (chr 155) (chr 187) (chr 231) (chr 171) (chr 153)) clean-s))
     "變電站")

    ;; 簡報室
    ((or (equal clean-s "簡報室")
         (vl-string-search "簡報室" clean-s)
         (vl-string-search (strcat (chr 194) (chr 178) (chr 179) (chr 248) (chr 171) (chr 199)) clean-s)
         (vl-string-search (strcat (chr 231) (chr 176) (chr 161) (chr 229) (chr 160) (chr 177) (chr 229) (chr 174) (chr 164)) clean-s))
     "簡報室")

    ;; 梯廳
    ((or (equal clean-s "梯廳")
         (vl-string-search "梯廳" clean-s)
         (vl-string-search (strcat (chr 177) (chr 232) (chr 198) (chr 85)) clean-s)
         (vl-string-search (strcat (chr 230) (chr 162) (chr 175) (chr 229) (chr 187) (chr 179)) clean-s))
     "梯廳")

    ;; 辦公室
    ((or (equal clean-s "辦公室")
         (vl-string-search "辦公室" clean-s)
         (vl-string-search (strcat (chr 191) (chr 236) (chr 164) (chr 189) (chr 171) (chr 199)) clean-s)
         (vl-string-search (strcat (chr 232) (chr 190) (chr 166) (chr 229) (chr 133) (chr 172) (chr 229) (chr 174) (chr 164)) clean-s))
     "辦公室")

    ;; 儲藏室
    ((or (equal clean-s "儲藏室")
         (vl-string-search "儲藏室" clean-s)
         (vl-string-search (strcat (chr 192) (chr 120) (chr 194) (chr 195) (chr 171) (chr 199)) clean-s)
         (vl-string-search (strcat (chr 229) (chr 132) (chr 178) (chr 232) (chr 151) (chr 143) (chr 229) (chr 174) (chr 164)) clean-s))
     "儲藏室")

    ;; 廁所
    ((or (equal clean-s "廁所")
         (vl-string-search "廁所" clean-s)
         (vl-string-search (strcat (chr 180) (chr 90) (chr 169) (chr 210)) clean-s)
         (vl-string-search (strcat (chr 229) (chr 187) (chr 129) (chr 230) (chr 137) (chr 128)) clean-s))
     "廁所")

    ;; 機房
    ((or (equal clean-s "機房")
         (vl-string-search "機房" clean-s)
         (vl-string-search (strcat (chr 190) (chr 247) (chr 169) (chr 208)) clean-s)
         (vl-string-search (strcat (chr 230) (chr 169) (chr 159) (chr 230) (chr 136) (chr 191)) clean-s))
     "機房")

    (t clean-s)
  )
)

;; Helper: Smart match space rule (returns (rule mode_type))
(defun cad-qc-find-rule-smart (label-str db / found clean-r clean-db-space ansi-db-space door-str door-list tag-item norm-label)
  (setq found nil)
  (setq norm-label (cad-normalize-room-name label-str))
  (setq clean-r (str-upcase (cad-clean-mtext norm-label)))

  (if (not (equal clean-r ""))
    (progn
      ;; 1. Try matching by Space Name (e.g. "變電站", "機房", "進氣機房")
      (foreach r db
        (setq clean-db-space (str-upcase (cad-clean-mtext (cad-normalize-room-name (car r)))))
        (setq ansi-db-space (str-upcase (cad-clean-mtext (cad-utf8-to-ansi (car r)))))

        (if (not (equal clean-db-space ""))
          (if (or (equal clean-r clean-db-space)
                  (equal clean-r ansi-db-space)
                  (vl-string-search clean-db-space clean-r)
                  (vl-string-search ansi-db-space clean-r)
                  (vl-string-search clean-r clean-db-space)
                  (vl-string-search clean-r ansi-db-space))
            (if (null found)
              (setq found r)
              (if (> (strlen (car r)) (strlen (car found)))
                (setq found r)
              )
            )
          )
        )
      )

      ;; 2. If not found, try matching by Door Tag / Door Schedule (e.g. "SD1-A", "SD1A", "D-01", "D01")
      (if (null found)
        (foreach r db
          (setq door-str (str-upcase (cdr (assoc "DOOR" (cdr r)))))
          (if (not (equal door-str ""))
            (progn
              (setq door-list (cad-split-string door-str ","))
              (foreach tag-item door-list
                (setq tag-item (str-upcase (vl-string-trim " \t\r\n" tag-item)))
                (if (and (not (equal tag-item ""))
                         (or (equal clean-r tag-item)
                             (and (>= (strlen tag-item) 3) (vl-string-search tag-item clean-r))))
                  (if (null found) (setq found r))
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

;; Command Aliases
(defun c:CADQC () (c:REVITQC))
(defun c:QC () (c:REVITQC))

(princ "\n[OK] cad_qc.lsp (Pure ASCII/English Code) loaded successfully! Type CADQC, QC or REVITQC in AutoCAD command line.")
(princ)
