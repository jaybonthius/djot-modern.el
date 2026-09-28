;;; gui-test.el --- Redisplay-level presentation regressions -*- lexical-binding: t; -*-
(require 'djot-modern-test)

(defmacro djot-modern-gui-test--buffer (text &rest body)
  "Display TEXT in a real window and evaluate BODY."
  (declare (indent 1))
  `(save-window-excursion
     (djot-modern-test--buffer ,text
       (delete-other-windows)
       (switch-to-buffer (current-buffer))
       (djot-modern-mode 1)
       (goto-char (point-min))
       (redisplay t) (sit-for 0.1)
       ,@body)))

(defun djot-modern-gui-test--xy (position)
  "Return the actual displayed pixel coordinates of POSITION."
  (posn-x-y (or (posn-at-point position) (error "Position %d not displayed" position))))

(defun djot-modern-gui-test--pipes ()
  "Return each real table row's displayed pipe x coordinates."
  (let (rows)
    (djot-map-nodes
     (lambda (row)
       (when (member (treesit-node-type row) '("table_header" "table_row"))
         (push (cl-loop for i below (treesit-node-child-count row)
                        for child = (treesit-node-child row i)
                        when (equal (treesit-node-type child) "|")
                        collect (car (djot-modern-gui-test--xy (treesit-node-end child)))) rows))))
    (nreverse rows)))

(ert-deftest djot-modern-gui-actual-fonts-and-scripts ()
  (should (display-graphic-p))
  (djot-modern-gui-test--buffer "Prose with H~2~O and x^2^.\n\n> Quoted prose.\n\n```elisp\n(defun hello () \"hello\")\n```\n\n| Key | Value |\n|-----|-------|\n| one | two |\n"
    (let ((prose (font-get (font-at (djot-modern-test--position "Prose")) :family))
          (quote (font-get (font-at (djot-modern-test--position "Quoted")) :family))
          (code (font-get (font-at (djot-modern-test--position "defun")) :family))
          (table (font-get (font-at (djot-modern-test--position "Key")) :family)))
      (should (equal prose quote))
      (should (equal code table))
      (should-not (equal prose code)))
    (let ((body (cdr (djot-modern-gui-test--xy (djot-modern-test--position "H~"))))
          (sub (cdr (djot-modern-gui-test--xy (djot-modern-test--position "2~"))))
          (sup (cdr (djot-modern-gui-test--xy (djot-modern-test--position "2^")))))
      (should (> sub body))
      (should (< sup sub)))))

(ert-deftest djot-modern-gui-table-pixels-and-incremental-edit ()
  (djot-modern-gui-test--buffer
      "| Key | Value |\n|-----|-------|\n| short | longer words |\n| `x|y` | a\\|b |\n\n[site](https://djot.net)\n"
    (let* ((pipes (djot-modern-gui-test--pipes))
           (link (cl-find-if (lambda (ov) (overlay-get ov 'djot-link))
                             (overlays-at (djot-modern-test--position "site")))))
      (should (cl-every (lambda (row) (equal row (car pipes))) pipes))
      (goto-char (djot-modern-test--position "short"))
      (insert "very much wider ")
      ;; Actual JIT/redisplay, not a whole-buffer font-lock-ensure shortcut.
      (redisplay t) (sit-for 0.2)
      (let ((new (djot-modern-gui-test--pipes)))
        (should (cl-every (lambda (row) (equal row (car new))) new))
        (should (> (nth 1 (car new)) (nth 1 (car pipes)))))
      (should (overlay-buffer link))
      (djot-modern-mode -1)
      (redisplay t)
      (should-not (djot-modern-test--owned)))))

(ert-deftest djot-modern-gui-last-row-deletion ()
  (djot-modern-gui-test--buffer
      "| Key | Value |\n|-----|-------|\n| one | two |\n| very long last cell | wider |\n\nFollowing prose.\n"
    (let ((width (nth 1 (car (djot-modern-gui-test--pipes)))))
      (goto-char (djot-modern-test--position "| very"))
      (delete-region (line-beginning-position) (line-beginning-position 2))
      (redisplay t) (sit-for 0.2)
      (should (< (nth 1 (car (djot-modern-gui-test--pipes))) width)))))

(ert-deftest djot-modern-gui-table-alignment-directives ()
  (djot-modern-gui-test--buffer
      "| Left | Right | Center |\n|:-----|------:|:------:|\n| long word | wider text | wide middle |\n| l | r | c |\n"
    (let ((right-short (car (djot-modern-gui-test--xy (djot-modern-test--position "r |"))))
          (right-long (car (djot-modern-gui-test--xy (djot-modern-test--position "wider text"))))
          (center-short (car (djot-modern-gui-test--xy (djot-modern-test--position "c |"))))
          (center-long (car (djot-modern-gui-test--xy (djot-modern-test--position "wide middle")))))
      (should (> right-short right-long))
      (should (> center-short center-long)))
    (let ((pipes (djot-modern-gui-test--pipes)))
      (should (cl-every (lambda (row) (equal row (car pipes))) pipes)))))

(ert-deftest djot-modern-gui-theme-and-font-refresh ()
  (djot-modern-gui-test--buffer "# Theme heading\n\n| Key | Value |\n|-----|-------|\n| one | longer words |\n"
    (let ((source (buffer-substring-no-properties (point-min) (point-max)))
          (original (face-attribute 'fixed-pitch :height))
          (width (car (last (car (djot-modern-gui-test--pipes))))))
      (unwind-protect
          (progn
            (set-face-attribute 'fixed-pitch nil :height 180)
            (redisplay t) (sit-for 0.2) (redisplay t)
            (should (> (car (last (car (djot-modern-gui-test--pipes)))) width))
            (dolist (theme '(modus-operandi-tinted modus-vivendi-tinted))
              (mapc #'disable-theme custom-enabled-themes)
              (load-theme theme t)
              (redisplay t) (sit-for 0.1) (redisplay t)
              (should (equal (face-foreground 'djot-modern-heading-1 nil t)
                             (face-foreground 'outline-1 nil t)))
              (should (equal source (buffer-substring-no-properties (point-min) (point-max))))))
        (set-face-attribute 'fixed-pitch nil :height original)))))

(ert-deftest djot-modern-gui-empty-cells ()
  (djot-modern-gui-test--buffer
      "# Empty cells\n\n|a||c|\n|:-|--:|:-:|\n||b|c|\n|a|b||\n||||\n|1|2|3|\n"
    (let ((pipes (djot-modern-gui-test--pipes)))
      (should (cl-every (lambda (row) (= (length row) 4)) pipes))
      (should (cl-every (lambda (row) (equal row (car pipes))) pipes)))
    (when (fboundp 'djot-modern-gui--capture)
      (djot-modern-gui--capture "empty-cells.png"))))

(provide 'gui-test)
;;; gui-test.el ends here
