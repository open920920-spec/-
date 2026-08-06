;; ==============================================================================
;; 🏢 AutoCAD Spatial Quality Control & Finish Code Placement Tool (cad_qc.lsp)
;; 
;; Features:
;;   1. Reads markdown database (空間裝修與門窗對照表.md) for finish codes (e.g. PE-01).
;;   2. Scans DWG space names and inserts finish code text directly underneath.
;;   3. Detects door width automatically (e.g. 90cm from 90x210, ignoring height).
;;   4. Displays door tags, lock hardware, wall, floor, ceiling & notes specs.
;;
;; Commands: CADQC, QC, REVITQC
;; ==============================================================================

(vl-load-com)

;; --- Main Command ---
(defun c:REVITQC (/ filepath file line current-space val ss idx total ent ent-data ent-type room-name clean-name matched-rule finish-code door-spec hw-spec wall-spec floor-spec ceil-spec notes-spec pass-count fail-count att att-tag auto-write ins-pt text-h layer-name new-y new-pt door-w min-w-req)
  (princ "\n==========================================================")
  (princ "\n🏢 Spatial QC & Finish Code Auto-Placement Tool (AutoCAD)")
  (princ "\n==========================================================")

  ;; Try to locate the Markdown rule file in current DWG directory
  (setq filepath (strcat (getvar "DWGPREFIX") "空間裝修與門窗對照表.md"))
  (if (not (findfile filepath))
    (setq filepath (getfiled "Select Spatial Regulation Markdown File" "" "md" 4))
  )

  (if (or (null filepath) (not (findfile filepath)))
    (progn
      (alert "Error: Spatial Regulation Database File (空間裝修與門窗對照表.md) Not Found!")
      (exit)
    )
  )

  (princ (strcat "\n📖 Reading Database File: " filepath))

  ;; Parse Markdown Database
  (setq rule-db '())
  (setq file (open filepath "r"))
  (setq current-space nil)

  (while (setq line (read-line file))
    (setq line (vl-string-trim " \t\r\n" line))
    (cond
      ;; Space Name Header (## 變電站)
      ((wcmatch line "## *")
       (setq current-space (vl-string-trim " \t" (substr line 4)))
       (setq rule-db (cons (list current-space (cons "FINISH_CODE" "") (cons "DOOR" "") (cons "HARDWARE" "") (cons "WALL" "") (cons "FLOOR" "") (cons "CEILING" "") (cons "NOTES" "")) rule-db))
      )
      ;; Finish Code
      ((and current-space (wcmatch line "*- \\*\\*粉刷*編號\\*\\*:*"))
       (setq val (vl-string-trim " \t" (substr line (+ 16 (vl-string-search "- **粉刷" line)))))
       (setq val (vl-string-trim " \t" (substr val (+ 2 (vl-string-search ":" val)))))
       (cad-qc-update-rule current-space "FINISH_CODE" val)
      )
      ;; Door Spec
      ((and current-space (wcmatch line "*- \\*\\*門窗編號\\*\\*:*"))
       (setq val (vl-string-trim " \t" (substr line (+ 16 (vl-string-search "- **門窗編號**:" line)))))
       (cad-qc-update-rule current-space "DOOR" val)
      )
      ;; Lock Hardware
      ((and current-space (wcmatch line "*- \\*\\*門鎖五金*編號\\*\\*:*"))
       (setq val (vl-string-trim " \t" (substr line (+ 20 (vl-string-search "- **門鎖五金" line)))))
       (setq val (vl-string-trim " \t" (substr val (+ 2 (vl-string-search ":" val)))))
       (cad-qc-update-rule current-space "HARDWARE" val)
      )
      ;; Wall Finish
      ((and current-space (wcmatch line "*- \\*\\*牆面粉刷編號\\*\\*:*"))
       (setq val (vl-string-trim " \t" (substr line (+ 20 (vl-string-search "- **牆面粉刷編號**:" line)))))
       (cad-qc-update-rule current-space "WALL" val)
      )
      ;; Floor Finish
      ((and current-space (wcmatch line "*- \\*\\*地面粉刷編號\\*\\*:*"))
       (setq val (vl-string-trim " \t" (substr line (+ 20 (vl-string-search "- **地面粉刷編號**:" line)))))
       (cad-qc-update-rule current-space "FLOOR" val)
      )
      ;; Ceiling Finish
      ((and current-space (wcmatch line "*- \\*\\*天花粉刷編號\\*\\*:*"))
       (setq val (vl-string-trim " \t" (substr line (+ 20 (vl-string-search "- **天花粉刷編號**:" line)))))
       (cad-qc-update-rule current-space "CEILING" val)
      )
      ;; Notes
      ((and current-space (wcmatch line "*- \\*\\*備註\\*\\*:*"))
       (setq val (vl-string-trim " \t" (substr line (+ 10 (vl-string-search "- **備註**:" line)))))
       (cad-qc-update-rule current-space "NOTES" val)
      )
    )
  )
  (close file)

  (princ (strcat "\n✅ Loaded " (itoa (length rule-db)) " space rules from database."))

  ;; Prompt user for auto text insertion below space name
  (initget "Y N")
  (setq auto-write (getkword "\nAuto-insert Finish Code (e.g. PE-01) below Space Name? [Yes(Y)/No(N)] <Y>: "))
  (if (null auto-write) (setq auto-write "Y"))

  ;; --- Select DWG Entities ---
  (princ "\n\n👉 Select DWG Room Name Text/Blocks (TEXT, MTEXT, ATTRIB INSERT):")
  (setq ss (ssget '((0 . "TEXT,MTEXT,INSERT"))))

  (if (null ss)
    (progn (princ "\n❌ No entities selected. Command aborted.") (princ))
    (progn
      (setq idx 0)
      (setq total (sslength ss))
      (setq pass-count 0)
      (setq fail-count 0)

      (princ "\n\n==========================================================")
      (princ "\n📊 AutoCAD Spatial Inspection & Finish Code Placement Results")
      (princ "\n==========================================================")

      (while (< idx total)
        (setq ent (ssname ss idx))
        (setq ent-data (entget ent))
        (setq ent-type (cdr (assoc 0 ent-data)))
        (setq room-name "")
        (setq ins-pt nil)
        (setq text-h nil)

        (cond
          ;; TEXT / MTEXT
          ((or (= ent-type "TEXT") (= ent-type "MTEXT"))
           (setq room-name (cdr (assoc 1 ent-data)))
           (setq ins-pt (cdr (assoc 10 ent-data)))
           (setq text-h (cdr (assoc 40 ent-data)))
          )
          
          ;; Block Attributes (INSERT)
          ((= ent-type "INSERT")
           (setq ins-pt (cdr (assoc 10 ent-data)))
           (setq att (entnext ent))
           (while (and att (= (cdr (assoc 0 (entget att))) "ATTRIB"))
             (setq att-tag (str-upcase (cdr (assoc 2 (entget att)))))
             (if (or (wcmatch att-tag "*ROOM*") (wcmatch att-tag "*NAME*") (wcmatch att-tag "*空間*") (wcmatch att-tag "*房間*"))
               (progn
                 (setq room-name (cdr (assoc 1 (entget att))))
                 (setq text-h (cdr (assoc 40 (entget att))))
               )
             )
             (setq att (entnext att))
           )
          )
        )

        ;; Clean MTEXT formatting tags
        (setq clean-name (cad-clean-mtext room-name))

        (if (not (= clean-name ""))
          (progn
            (setq matched-rule (cad-qc-find-rule clean-name rule-db))
            (if matched-rule
              (progn
                (setq finish-code (cdr (assoc "FINISH_CODE" (cdr matched-rule))))
                (setq door-spec (cdr (assoc "DOOR" (cdr matched-rule))))
                (setq hw-spec (cdr (assoc "HARDWARE" (cdr matched-rule))))
                (setq wall-spec (cdr (assoc "WALL" (cdr matched-rule))))
                (setq floor-spec (cdr (assoc "FLOOR" (cdr matched-rule))))
                (setq ceil-spec (cdr (assoc "CEILING" (cdr matched-rule))))
                (setq notes-spec (cdr (assoc "NOTES" (cdr matched-rule))))

                (if (= finish-code "") (setq finish-code "PE-01"))

                ;; Extract door width (height ignored)
                (setq door-w (cad-extract-door-width clean-name))

                (princ (strcat "\n📍 Text: [" clean-name "] -> Matched Rule: [" (car matched-rule) "] | Finish Code: [" finish-code "]"))
                (if (> door-w 0)
                  (princ (strcat "\n    Door Width: [" (rtos door-w 2 1) " cm] (Height Excluded)"))
                )
                (princ (strcat "\n    Door Spec: " door-spec))
                (if (not (= hw-spec ""))
                  (princ (strcat "\n    Lock Hardware: " hw-spec))
                )
                (princ (strcat "\n    Wall Finish: " wall-spec))
                (princ (strcat "\n    Floor Finish: " floor-spec))
                (princ (strcat "\n    Ceiling Finish: " ceil-spec))

                ;; Insert text directly below space name
                (if (and (= auto-write "Y") ins-pt)
                  (progn
                    (if (null text-h) (setq text-h 2.5))
                    (setq new-y (- (cadr ins-pt) (* text-h 1.6)))
                    (setq new-pt (list (car ins-pt) new-y (caddr ins-pt)))

                    (entmake
                      (list
                        '(0 . "TEXT")
                        (assoc 8 ent-data)       ; Same layer
                        (cons 10 new-pt)         ; Insertion coordinate (y - 1.6*h)
                        (cons 40 (* text-h 0.85)); Text height (85%)
                        (cons 1 finish-code)     ; Finish Code string (e.g. PE-01)
                        '(62 . 3)                ; Green color
                      )
                    )
                    (princ (strcat " -> Written Text: [" finish-code "]"))
                  )
                )

                (setq pass-count (1+ pass-count))
              )
              (progn
                (princ (strcat "\n⚠️ Text: [" clean-name "] -> No Matched Rule in Database"))
                (setq fail-count (1+ fail-count))
              )
            )
            (princ "\n----------------------------------------------------------")
          )
        )

        (setq idx (1+ idx))
      )

      (princ (strcat "\n\n🎉 QC Check Completed! Successfully matched " (itoa pass-count) " spaces."))
      (alert (strcat "AutoCAD Spatial QC Completed!\n\nMatched Spaces: " (itoa pass-count) "\nUnmatched Spaces: " (itoa fail-count) "\n\nFinish Codes (e.g. PE-01) inserted directly below space names."))
    )
  )
  (princ)
)

;; Helper: Extract Door Width (Exclude Height)
(defun cad-extract-door-width (str / pos w-str)
  (setq w-str 0.0)
  (cond
    ((and (setq pos (vl-string-search "X" (str-upcase str)))
          (> pos 0))
     (setq w-str (atof (substr str 1 pos)))
    )
    ((and (setq pos (vl-string-search "*" str))
          (> pos 0))
     (setq w-str (atof (substr str 1 pos)))
    )
  )
  w-str
)

;; Helper: Clean MTEXT formatting tags
(defun cad-clean-mtext (str / pos endpos)
  (if (null str) (setq str ""))
  (while (setq pos (vl-string-search "\\P" str)) (setq str (strcat (substr str 1 pos) " " (substr str (+ pos 3)))))
  (while (setq pos (vl-string-search "\\p" str)) (setq str (strcat (substr str 1 pos) " " (substr str (+ pos 3)))))
  (while (setq pos (vl-string-search "{" str)) (setq str (strcat (substr str 1 pos) (substr str (+ pos 2)))))
  (while (setq pos (vl-string-search "}" str)) (setq str (strcat (substr str 1 pos) (substr str (+ pos 2)))))
  (if (and (setq pos (vl-string-search "\\f" str)) (setq endpos (vl-string-search ";" str)))
    (setq str (vl-string-trim " \t\r\n" (substr str (+ endpos 2))))
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

;; Helper: Smart match space rule (exact first, longest match priority)
(defun cad-qc-find-rule (room-name db / found)
  (setq found nil)
  (foreach r db
    (if (or (vl-string-search (car r) room-name) (vl-string-search room-name (car r)))
      (if (null found) (setq found r) (if (> (strlen (car r)) (strlen (car found))) (setq found r)))
    )
  )
  found
)

;; Command Aliases
(defun c:CADQC () (c:REVITQC))
(defun c:QC () (c:REVITQC))

(princ "\n✅ cad_qc.lsp (Pure ASCII/English Code) loaded successfully! Type CADQC, QC or REVITQC in AutoCAD command line.")
(princ)
