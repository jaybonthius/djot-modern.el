;;; djot-modern-test.el --- Base-mode integration and lifecycle -*- lexical-binding: t; -*-

(require 'ert)
(require 'djot-modern)
(unless (treesit-ready-p 'djot t)
  (error "Set GRAMMAR_DIR to a directory containing libtree-sitter-djot"))

(defconst djot-modern-test--document
  "# Title\n\n## Second\n\n### Third\n\n#### Fourth\n\n##### Fifth\n\n###### Sixth\n\nProse _emphasis_ and *strong*, H~2~O and x^2^. [site](https://djot.net).\n\n- bullet\n- [ ] pending\n- [x] done\n\n> Quoted prose.\n\n```elisp\n(defun hello ()\n  \"A native string.\"\n  (message \"Hello\"))\n```\n\n```=html\n# Raw *literal*\n```\n\n::: note\nBody with [span]{.note key=\"value\"}.\n:::\n\n{#water}\n{.important .large}\nDon't forget the water.\n\n| Key | Value |\n|:----|------:|\n| `x|y` | a\\|b |\n\n*Unfinished and \\*escaped\\*.\n")

(defmacro djot-modern-test--buffer (text &rest body)
  "Evaluate BODY in a base Djot buffer containing TEXT."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (rename-buffer (generate-new-buffer-name "djot-modern-test"))
     (insert ,text)
     (djot-mode)
     (setq-local djot-hide-markup t)
     (font-lock-ensure)
     (set-buffer-modified-p nil)
     (let ((noninteractive nil))
       (unwind-protect (progn ,@body)
         (when djot-modern-mode (djot-modern-mode -1))))))

(defun djot-modern-test--position (text)
  "Return the start of TEXT in the current buffer."
  (save-excursion (goto-char (point-min)) (search-forward text)
                  (- (point) (length text))))

(defun djot-modern-test--property (text property)
  "Return effective PROPERTY at TEXT."
  (get-char-property (djot-modern-test--position text) property))

(defun djot-modern-test--owned (&optional position)
  "Return modern overlays at POSITION or in the accessible buffer."
  (cl-remove-if-not (lambda (ov) (overlay-get ov 'djot-modern))
                    (if position (overlays-at position)
                      (overlays-in (point-min) (point-max)))))

(ert-deftest djot-modern-requires-base-mode ()
  (with-temp-buffer
    (text-mode)
    (should-error (djot-modern-mode 1) :type 'user-error)
    (should-not djot-modern-mode)
    (should-not (treesit-parser-list))
    (should-not djot-modern--remappings)))

(ert-deftest djot-modern-preserves-base-capabilities ()
  (djot-modern-test--buffer djot-modern-test--document
    (let* ((parser djot-parser)
           (rules treesit-font-lock-settings)
           (native (get-text-property (djot-modern-test--position "defun") 'face))
           (link (djot-modern-test--position "site")))
      (should (memq 'font-lock-keyword-face native))
      (dotimes (_ 3)
        (djot-modern-mode 1)
        (should (eq parser djot-parser))
        (should (= 1 (length (treesit-parser-list))))
        (should (eq rules treesit-font-lock-settings))
        (should (equal native (get-text-property (djot-modern-test--position "defun") 'face)))
        (should (keymapp (get-char-property link 'keymap)))
        (should (get-char-property link 'help-echo))
        (should (invisible-p (djot-modern-test--position "*strong")))
        (djot-modern-mode -1)
        (should-not (djot-modern-test--owned))
        (should-not djot-modern--remappings)
        (should (keymapp (get-char-property link 'keymap)))
        (should (invisible-p (djot-modern-test--position "*strong")))
        (should (equal native (get-text-property (djot-modern-test--position "defun") 'face)))))))

(ert-deftest djot-modern-typography-and-symbols ()
  (djot-modern-test--buffer djot-modern-test--document
    (djot-modern-mode 1)
    (should (memq 'variable-pitch (cdr (assq 'default face-remapping-alist))))
    (cl-loop for title in '("Title" "Second" "Third" "Fourth" "Fifth" "Sixth")
             for level from 1 do
             (should (eq (djot-modern-test--property title 'face)
                         (intern (format "djot-modern-heading-%d" level)))))
    (should (equal (djot-modern-test--property "# Title" 'display) "◉"))
    (should (equal (djot-modern-test--property "- bullet" 'display) "–"))
    (should (equal (djot-modern-test--property "- [ ]" 'display) "□"))
    (should (equal (djot-modern-test--property "- [x]" 'display) "☑"))
    (should (equal (djot-modern-test--property "2~" 'display) '((height 0.8) (raise -0.2))))
    (should (equal (djot-modern-test--property "2^" 'display) '((height 0.8) (raise 0.3))))
    (should (eq (djot-modern-test--property "Quoted" 'face) 'djot-modern-quote))
    (should (eq (djot-modern-test--property "defun" 'face) 'djot-modern-code))
    (should (eq (djot-modern-test--property ".important" 'face) 'djot-modern-label))))

(ert-deftest djot-modern-explicit-source-display ()
  (djot-modern-test--buffer djot-modern-test--document
    (djot-modern-mode 1)
    (goto-char (djot-modern-test--position "# Title"))
    (run-hooks 'post-command-hook)
    (should (get-char-property (point) 'display))
    (djot-show-source 1)
    (dolist (text '("# Title" "- bullet" "- [ ]" "2~" "2^" "{#water}" "```elisp"))
      (should-not (djot-modern-test--property text 'display)))
    (should-not (invisible-p (djot-modern-test--position "*strong")))
    (djot-show-source -1)
    (should (djot-modern-test--property "# Title" 'display))
    (should (invisible-p (djot-modern-test--position "*strong")))))

(ert-deftest djot-modern-source-point-undo-and-copy ()
  (djot-modern-test--buffer djot-modern-test--document
    (buffer-enable-undo)
    (goto-char 20)
    (let ((source (buffer-substring-no-properties (point-min) (point-max)))
          (undo buffer-undo-list)
          (position (point))
          (buffer-read-only t))
      (dotimes (_ 3)
        (djot-modern-mode 1)
        (djot-refresh)
        (should (equal source (filter-buffer-substring (point-min) (point-max))))
        (should (= position (point)))
        (should (eq undo buffer-undo-list))
        (should-not (buffer-modified-p))
        (djot-modern-mode -1))
      (should (equal source (buffer-substring-no-properties (point-min) (point-max)))))
    (djot-modern-mode 1)
    (setq buffer-undo-list nil)
    (goto-char (point-max))
    (undo-boundary)
    (insert "edited")
    (undo-boundary)
    (let ((undo buffer-undo-list))
      (djot-refresh)
      (should (eq undo buffer-undo-list)))
    (let ((inhibit-message t)) (undo 1))
    (should (equal djot-modern-test--document (buffer-substring-no-properties (point-min) (point-max))))))

(ert-deftest djot-modern-foreign-properties-and-remaps ()
  (djot-modern-test--buffer "# Title\n\nPlain prose.\n"
    (let* ((foreign (make-overlay 1 2))
           (cookie (face-remap-add-relative 'default '(:height 1.1))))
      (overlay-put foreign 'display "FOREIGN")
      (put-text-property 3 4 'line-prefix "foreign-prefix")
      (setq-local line-spacing 0.3)
      (djot-modern-mode 1)
      (should (equal (get-char-property 1 'display) "FOREIGN"))
      (djot-modern-mode 1)
      (djot-modern-mode -1)
      (should (= line-spacing 0.3))
      (should (overlay-buffer foreign))
      (should (equal (get-text-property 3 'line-prefix) "foreign-prefix"))
      (should (member '(:height 1.1) (cdr (assq 'default face-remapping-alist))))
      (face-remap-remove-relative cookie))))

(ert-deftest djot-modern-literal-and-unmatched-source ()
  (djot-modern-test--buffer
      "\\*escaped\\* and *unfinished\n\n`*literal* # x^2^ |`\n\n```=html\n# Raw *literal*\n- [ ] raw\n```\n\n| a\\|b | `x|y` |\n|-----|-----|\n"
    (djot-modern-mode 1)
    (dolist (text '("\\*escaped" "*unfinished" "*literal* #" "# Raw" "- [ ] raw" "|b" "|y"))
      (should-not (djot-modern-test--property text 'display))
      (should-not (invisible-p (djot-modern-test--position text))))))

(ert-deftest djot-modern-bounded-refontification-and-edit ()
  (djot-modern-test--buffer djot-modern-test--document
    (djot-modern-mode 1)
    (let* ((position (djot-modern-test--position "Quoted"))
           (quote (car (djot-modern-test--owned position)))
           (count (length (djot-modern-test--owned))))
      (dotimes (_ 3) (djot-refresh 1 8))
      (should (overlay-buffer quote))
      (should (= count (length (djot-modern-test--owned))))
      ;; A fontification slice through a replacement must not duplicate it.
      (djot-refresh 1 2)
      (should (= 1 (length (cl-remove-if-not
                            (lambda (ov) (overlay-get ov 'display))
                            (djot-modern-test--owned 1)))))
      (goto-char 1)
      (delete-char 2)
      (djot-refresh 1 (line-end-position))
      (should-not (get-char-property 1 'display))
      (should (overlay-buffer quote)))))

(ert-deftest djot-modern-major-mode-and-narrowing-teardown ()
  (djot-modern-test--buffer djot-modern-test--document
    (djot-modern-mode 1)
    (narrow-to-region 20 60)
    (djot-modern-mode -1)
    (widen)
    (should-not (djot-modern-test--owned))
    (djot-modern-mode 1)
    (text-mode)
    (should-not (djot-modern-test--owned))
    (should-not (local-variable-p 'line-spacing))
    (should-not djot-modern--remappings)))

(ert-deftest djot-modern-options-and-global-opt-in ()
  (let ((djot-modern-prose-face nil)
        (djot-modern-headings nil)
        (djot-modern-lists nil)
        (djot-modern-blocks nil)
        (djot-modern-inline nil)
        (djot-modern-tables nil))
    (djot-modern-test--buffer djot-modern-test--document
      (djot-modern-mode 1)
      (should-not (assq 'default face-remapping-alist))
      (should-not (djot-modern-test--property "# Title" 'display))
      (should-not (djot-modern-test--property "- bullet" 'display))
      (should-not (djot-modern-test--property "2^" 'display))))
  (should-not global-djot-modern-mode)
  (unwind-protect
      (progn
        (global-djot-modern-mode 1)
        (with-temp-buffer (text-mode) (should-not djot-modern-mode))
        (with-temp-buffer (djot-mode) (run-hooks 'after-change-major-mode-hook)
                          (should djot-modern-mode)))
    (global-djot-modern-mode -1)))

(ert-deftest djot-modern-option-change-and-narrowed-enable ()
  (djot-modern-test--buffer djot-modern-test--document
    (setq-local line-spacing 0.4)
    (let ((djot-modern-line-spacing 0.15))
      (narrow-to-region 20 60)
      (djot-modern-mode 1)
      (should (= (point-min) 20))
      (widen)
      (should (djot-modern-test--property "# Title" 'display))
      (setq djot-modern-line-spacing 0.2)
      (djot-modern-mode 1)
      (should (= line-spacing 0.2))
      (djot-modern-mode -1)
      (should (= line-spacing 0.4)))))

(ert-deftest djot-modern-font-lock-toggle ()
  (djot-modern-test--buffer "# Title\n\n- item\n"
    (font-lock-mode 1)
    (djot-modern-mode 1)
    (should (djot-modern-test--owned))
    (font-lock-mode -1)
    (should-not (djot-modern-test--owned))
    (font-lock-mode 1)
    (should (djot-modern-test--owned))))

(ert-deftest djot-modern-real-anchor-following-on-and-off ()
  (djot-modern-test--buffer "[jump](#target)\n\n# target\n\nBody.\n"
    (dolist (state '(1 -1 1))
      (djot-modern-mode state)
      (goto-char (djot-modern-test--position "jump"))
      (djot-open-at-point)
      (should (= (line-number-at-pos) 3)))))

(ert-deftest djot-modern-quoted-technical-text-stays-technical ()
  (djot-modern-test--buffer "> Quoted prose.\n>\n> ```elisp\n> (message \"hello\")\n> ```\n"
    (djot-modern-mode 1)
    (should (eq (djot-modern-test--property "Quoted" 'face) 'djot-modern-quote))
    (should-not
     (cl-some (lambda (overlay) (eq (overlay-get overlay 'face) 'djot-modern-quote))
              (djot-modern-test--owned (djot-modern-test--position "message"))))))

(provide 'djot-modern-test)
;;; djot-modern-test.el ends here
