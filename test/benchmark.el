;;; benchmark.el --- Bounded presentation and edit timings -*- lexical-binding: t; -*-
(require 'benchmark)
(require 'djot-modern)
(unless (treesit-ready-p 'djot t) (error "Set GRAMMAR_DIR to the Djot grammar"))
(defconst djot-modern-benchmark--sample
  "# A heading\n\nProse with *strong*, _emphasis_ and [site](https://djot.net).\n\n- item\n- [x] done\n\n```elisp\n(message \"Hello\")\n```\n\n| Key | Value |\n|-----|-------|\n| short | longer text |\n\n")
(princ (format "Emacs %s; grammar ABI %s; directory %s; graphics %s\n"
               emacs-version (treesit-language-abi-version 'djot)
               treesit-extra-load-path (display-graphic-p)))
(dolist (count '(20 100 300))
  (with-temp-buffer
    (rename-buffer (generate-new-buffer-name "Djot benchmark"))
    (dotimes (_ count) (insert djot-modern-benchmark--sample))
    (let* ((gc-cons-threshold (* 16 1024 1024))
           (noninteractive nil)
           (base (benchmark-run 1 (djot-mode) (font-lock-ensure)))
           (initial (benchmark-run 1 (djot-modern-mode 1)))
           (distant (cl-find-if (lambda (ov) (overlay-get ov 'djot-modern))
                                (overlays-at (- (point-max) 12)))))
      (goto-char (point-min))
      (search-forward "Prose")
      (let ((edit (benchmark-run 1 (insert " revised")
                                 (font-lock-ensure (line-beginning-position) (line-end-position)))))
        (unless (and distant (overlay-buffer distant))
          (error "Bounded edit replaced distant presentation"))
        (let ((overlays (length (overlays-in (point-min) (point-max))))
              (disable (benchmark-run 1 (djot-modern-mode -1))))
          (princ (format "%d headings %d bytes base=%.6fs modern=%.6fs bounded-edit=%.6fs disable=%.6fs overlays=%d parsers=%d\n"
                         count (buffer-size) (car base) (car initial) (car edit) (car disable)
                         overlays (length (treesit-parser-list)))))))))
;;; benchmark.el ends here
