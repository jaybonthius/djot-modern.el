;;; checkdoc.el --- Fail the check on documentation warnings -*- lexical-binding: t; -*-

(require 'checkdoc)
(checkdoc-file "djot-modern.el")
(when-let* ((buffer (get-buffer checkdoc-diagnostic-buffer)))
  (with-current-buffer buffer
    (when (> (buffer-size) 0)
      (princ (buffer-string))
      (kill-emacs 1))))

;;; checkdoc.el ends here
