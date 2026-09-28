;;; gui.el --- Actual Org-modern and Djot-modern visual comparison -*- lexical-binding: t; -*-

;; Run under Xvfb with a graphical Emacs -Q, both packages on load-path,
;; ORG_MODERN_DIR and COMPAT_DIR on load-path, GRAMMAR_DIR, DJOT_GUI_DIR.
(require 'cl-lib)
(defun djot-modern-gui--write (name text)
  "Write TEXT to artifact NAME."
  (with-temp-file (expand-file-name name (getenv "DJOT_GUI_DIR")) (insert text)))
(defun djot-modern-gui--capture (name)
  "Capture the current frame as NAME after real redisplay."
  (redisplay t)
  (sit-for 0.3)
  (let ((coding-system-for-write 'no-conversion))
    (write-region (x-export-frames nil 'png) nil
                  (expand-file-name name (getenv "DJOT_GUI_DIR")) nil 'silent)))
(defun djot-modern-gui--scroll (window text)
  "Scroll WINDOW to TEXT."
  (with-selected-window window
    (goto-char (point-min)) (search-forward text)
    (beginning-of-line) (set-window-start window (point)) (set-window-point window (point))))

(condition-case error-data
    (progn
      (let ((old-error (expand-file-name "error.txt" (getenv "DJOT_GUI_DIR"))))
        (when (file-exists-p old-error) (delete-file old-error)))
      (load (expand-file-name "test/setup.el" default-directory) nil t)
      (require 'djot-modern)
      (require 'org)
      (require 'org-modern)
      (require-theme 'modus-themes)
      (setq inhibit-startup-screen t)
      (set-face-attribute 'default nil :family "Fira Code" :height 130)
      (set-face-attribute 'fixed-pitch nil :family "Fira Code")
      (set-face-attribute 'variable-pitch nil :family "Noto Sans")
      (menu-bar-mode -1) (tool-bar-mode -1) (scroll-bar-mode -1)
      (set-frame-size (selected-frame) 1600 1150 t)
      (let ((org-buffer (find-file-noselect "example.org"))
            (djot-buffer (find-file-noselect "example.djot")))
        (with-current-buffer org-buffer
          (org-mode)
          (visual-line-mode 1)
          (setq-local org-hide-emphasis-markers t org-pretty-entities t
                      org-fontify-quote-and-verse-blocks t line-spacing 0.15)
          (face-remap-add-relative 'default 'variable-pitch)
          (face-remap-add-relative 'org-quote 'variable-pitch)
          (dolist (face '(org-block org-code org-verbatim org-table org-meta-line))
            (face-remap-add-relative face 'fixed-pitch))
          (cl-loop for scale in '(1.35 1.2 1.1 1.0 1.0 1.0) for level from 1 do
                   (face-remap-add-relative (intern (format "org-level-%d" level)) `(:height ,scale)))
          (setq-local org-modern-star 'replace org-modern-table-vertical 1)
          (org-modern-mode 1)
          (font-lock-ensure))
        (with-current-buffer djot-buffer
          (djot-mode) (visual-line-mode 1) (setq-local djot-hide-markup t)
          (djot-modern-mode 1))
        (delete-other-windows) (switch-to-buffer org-buffer)
        (let ((left (selected-window)) (right (split-window-right)))
          (set-window-buffer right djot-buffer)
          (dolist (theme '(modus-operandi-tinted modus-vivendi-tinted))
            (mapc #'disable-theme custom-enabled-themes)
            (load-theme theme t)
            (with-current-buffer org-buffer (font-lock-flush) (font-lock-ensure))
            (with-current-buffer djot-buffer (djot-refresh))
            (dolist (section '("A quieter page" "Small commitments" "A borrowed thought" "Code, not decoration" "A modest table"))
              (djot-modern-gui--scroll left section)
              (djot-modern-gui--scroll right section)
              (djot-modern-gui--capture (format "%s-%s.png" theme (replace-regexp-in-string "[^a-z]+" "-" (downcase section))))))
          (djot-modern-gui--scroll left "Code, not decoration")
          (djot-modern-gui--scroll right "Code, not decoration")
          (with-current-buffer djot-buffer
            (djot-modern-mode -1))
          (djot-modern-gui--capture "modern-off.png")
          (with-current-buffer djot-buffer
            (djot-modern-mode 1)
            (djot-show-source 1))
          (djot-modern-gui--capture "explicit-source.png")
          (with-current-buffer djot-buffer (djot-show-source -1)))
        (djot-modern-gui--write
         "environment.txt"
         (format "Emacs %s\nFeatures %s\nDefault actual %S\nVariable actual %S\nFixed actual %S\nOrg-modern %s\nNo user init; matched font/spacing/scales; modern left Org, right Djot.\n"
                 emacs-version system-configuration-features
                 (aref (font-info (face-font 'default)) 0) (aref (font-info (face-font 'variable-pitch)) 0)
                 (aref (font-info (face-font 'fixed-pitch)) 0) (locate-library "org-modern"))))
      (load (expand-file-name "test/djot-modern-test.el" default-directory) nil t)
      (load (expand-file-name "test/table-integration-test.el" default-directory) nil t)
      (load (expand-file-name "test/gui-test.el" default-directory) nil t)
      (let ((stats (ert-run-tests-batch t)))
        (djot-modern-gui--write "ert.txt"
         (mapconcat (lambda (test)
                      (let ((result (ert-test-most-recent-result test)))
                        (format "%s %s %s" (ert-test-name test)
                                (type-of result)
                                (if (ert-test-failed-p result)
                                    (ert-test-failed-condition result) ""))))
                    (ert-select-tests t t) "\n"))
        (unless (zerop (ert-stats-completed-unexpected stats)) (error "GUI ERT failed")))
      (kill-emacs 0))
  (error (djot-modern-gui--write "error.txt" (format "%S\n" error-data)) (kill-emacs 1)))
;;; gui.el ends here
