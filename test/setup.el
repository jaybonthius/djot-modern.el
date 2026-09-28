;;; setup.el --- Reproducible batch environment -*- lexical-binding: t; -*-

(require 'treesit)
(require 'subr-x)
(when-let* ((directory (or (getenv "GRAMMAR_DIR") (getenv "DJOT_GRAMMAR_DIR")))
            ((not (string-empty-p directory))))
  (add-to-list 'treesit-extra-load-path directory))
(setq load-prefer-newer t)

;;; setup.el ends here
