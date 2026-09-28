;;; djot-modern.el --- Quiet, editable Djot typography -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jay Bonthius
;; Author: Jay Bonthius
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: text, faces
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A presentation minor mode for Djot, inspired by org-modern.  Requires
;; the tree-sitter-djot grammar, not a particular major mode.  Enable in
;; a text-mode or djot-ts-mode buffer with M-x djot-modern-mode.
;; Source remains visible and editable; only structural markers receive
;; display replacements.  No parser installation or file association is
;; performed automatically.  See README.org for setup and limitations.

;;; Code:

(require 'cl-lib)
(require 'font-lock)
(require 'treesit)
(require 'subr-x)

(defgroup djot-modern nil
  "Quiet, editable Djot typography."
  :group 'text :group 'faces)

(defcustom djot-modern-headings t
  "Style headings with a size hierarchy and compact markers."
  :type 'boolean :group 'djot-modern)
(defcustom djot-modern-lists t
  "Style list markers and replace bullets and task boxes."
  :type 'boolean :group 'djot-modern)
(defcustom djot-modern-blocks t
  "Style code, raw blocks, quotes, div fences and thematic breaks."
  :type 'boolean :group 'djot-modern)
(defcustom djot-modern-tables t
  "Style table headers, pipes, separators and captions."
  :type 'boolean :group 'djot-modern)
(defcustom djot-modern-inline t
  "Style inline emphasis, links, code, math and attributes."
  :type 'boolean :group 'djot-modern)
(defcustom djot-modern-replace-markers t
  "Replace structural markers with glyphs without changing source text.
When nil, retain source markers and apply faces only.  Inline delimiters
always remain visible.  Toggle the mode after changing any option."
  :type 'boolean :group 'djot-modern)

(defface djot-modern-heading-1 '((t :inherit variable-pitch :weight bold :height 1.35))
  "First-level heading." :group 'djot-modern)
(defface djot-modern-heading-2 '((t :inherit variable-pitch :weight bold :height 1.2))
  "Second-level heading." :group 'djot-modern)
(defface djot-modern-heading-3 '((t :inherit variable-pitch :weight bold :height 1.1))
  "Third-level heading." :group 'djot-modern)
(defface djot-modern-heading-4 '((t :inherit variable-pitch :weight bold))
  "Deeper heading." :group 'djot-modern)
(defface djot-modern-marker '((t :inherit shadow))
  "Visible structural punctuation." :group 'djot-modern)
(defface djot-modern-label '((t :inherit (shadow fixed-pitch) :box (:line-width -1)))
  "Code language labels and attributes." :group 'djot-modern)
(defface djot-modern-code '((t :inherit fixed-pitch :extend t))
  "Code and raw text." :group 'djot-modern)
(defface djot-modern-strong '((t :weight bold))
  "Strong text." :group 'djot-modern)
(defface djot-modern-emphasis '((t :slant italic))
  "Emphasized text." :group 'djot-modern)
(defface djot-modern-highlight '((t :inherit highlight))
  "Highlighted text." :group 'djot-modern)
(defface djot-modern-insert '((t :inherit success :underline t))
  "Inserted text." :group 'djot-modern)
(defface djot-modern-delete '((t :inherit shadow :strike-through t))
  "Deleted text." :group 'djot-modern)
(defface djot-modern-script '((t :height 0.85))
  "Subscripts and superscripts, with visible source delimiters." :group 'djot-modern)
(defface djot-modern-link '((t :inherit link))
  "Link text, without adding navigation behavior." :group 'djot-modern)
(defface djot-modern-checked '((t :inherit success))
  "Completed task marker." :group 'djot-modern)
(defface djot-modern-table '((t :inherit fixed-pitch))
  "Table cells, preserving source alignment." :group 'djot-modern)

(defconst djot-modern--faces
  '(djot-modern-heading-1 djot-modern-heading-2 djot-modern-heading-3
    djot-modern-heading-4 djot-modern-marker djot-modern-label djot-modern-code
    djot-modern-strong djot-modern-emphasis djot-modern-highlight
    djot-modern-insert djot-modern-delete djot-modern-script djot-modern-link
    djot-modern-checked djot-modern-table))

(defconst djot-modern--keywords '((djot-modern--match (0 nil))))
(defvar-local djot-modern--parser nil)
(defvar-local djot-modern--owns-parser nil)
(defvar-local djot-modern--query nil)
(defvar-local djot-modern--font-lock-was-enabled nil)
(defvar-local djot-modern--active nil)

(defun djot-modern--patterns ()
  "Return query patterns for the enabled features."
  (append
   (when djot-modern-headings
     '((heading) @heading
       (heading (marker) @heading-marker)
       (heading (content (marker) @heading-marker))))
   (when djot-modern-lists
     '([(list_marker_dash) (list_marker_plus) (list_marker_star)] @bullet
       (list_marker_task (unchecked) @unchecked)
       (list_marker_task (checked) @checked)
       [(list_marker_definition)
        (list_marker_decimal_period) (list_marker_decimal_paren)
        (list_marker_decimal_parens) (list_marker_lower_alpha_period)
        (list_marker_lower_alpha_paren) (list_marker_lower_alpha_parens)
        (list_marker_upper_alpha_period) (list_marker_upper_alpha_paren)
        (list_marker_upper_alpha_parens) (list_marker_lower_roman_period)
        (list_marker_lower_roman_paren) (list_marker_lower_roman_parens)
        (list_marker_upper_roman_period) (list_marker_upper_roman_paren)
        (list_marker_upper_roman_parens)] @marker))
   (when djot-modern-blocks
     '([(code_block) (raw_block) (frontmatter)] @code
       [(code_block_marker_begin) (code_block_marker_end)
        (raw_block_marker_begin) (raw_block_marker_end)
        (frontmatter_marker) (div_marker_begin) (div_marker_end)] @marker
       (language) @label
       (block_quote_marker) @quote
       (thematic_break) @rule))
   (when djot-modern-tables
     '([(table_header) (table_row)] @table
       (table_header) @strong
       (table_header "|" @pipe)
       (table_row "|" @pipe)
       (table_separator) @marker
       (table_caption) @emphasis))
   (when djot-modern-inline
     '((emphasis) @emphasis (strong) @strong
       (insert) @insert (delete) @delete (highlighted) @highlight
       [(subscript) (superscript)] @script
       [(verbatim) (raw_inline) (math)] @code
       [(link_text) (autolink)] @link
       [(inline_link_destination) (link_destination) (link_label)
        (reference_label)] @marker
       [(inline_attribute) (block_attribute)] @label
       [(emphasis_begin) (emphasis_end) (strong_begin) (strong_end)
        (superscript_begin) (superscript_end) (subscript_begin) (subscript_end)
        (highlighted_begin) (highlighted_end) (insert_begin) (insert_end)
        (delete_begin) (delete_end) (verbatim_marker_begin) (verbatim_marker_end)
        (math_marker) (math_marker_begin) (math_marker_end)] @marker))))

(defun djot-modern--clear (beg end &rest _ignored)
  "Remove only our decorations between BEG and END."
  (with-silent-modifications
    (let ((pos beg) next)
      (while (< pos end)
        (setq next (next-single-property-change pos 'djot-modern--display nil end))
        (when-let* ((ours (get-text-property pos 'djot-modern--display)))
          (let ((at pos) stop)
            (while (< at next)
              (setq stop (next-single-property-change at 'display nil next))
              (when (eq ours (get-text-property at 'display))
                (remove-text-properties at stop '(display nil)))
              (setq at stop)))
          (remove-text-properties pos next '(djot-modern--display nil)))
        (setq pos next)))
    (let ((pos beg) next face)
      (while (< pos end)
        (setq next (next-single-property-change pos 'face nil end)
              face (get-text-property pos 'face))
        (cond
         ((memq face djot-modern--faces)
          (remove-text-properties pos next '(face nil)))
         ((and (consp face) (not (keywordp (car face))))
          (let ((clean (cl-set-difference face djot-modern--faces)))
            (unless (equal face clean)
              (if clean (put-text-property pos next 'face clean)
                (remove-text-properties pos next '(face nil)))))))
        (setq pos next)))))

(defun djot-modern--filter-substring (text)
  "Return TEXT without this mode's buffer-specific decorations."
  (with-temp-buffer
    (insert text)
    (djot-modern--clear (point-min) (point-max))
    (buffer-string)))

(defun djot-modern--paint (beg end face &optional glyph)
  "Apply FACE and optional GLYPH between BEG and END.
Never replace an existing display property owned by another package."
  (when (< beg end)
    (font-lock-prepend-text-property beg end 'face face)
    (when (and glyph djot-modern-replace-markers)
      ;; Some grammar markers include indentation or a terminating newline.
      ;; Replacing those would collapse nesting or join separate display lines.
      (save-excursion
        (goto-char beg)
        (skip-chars-forward " \t" end)
        (setq beg (point))
        (goto-char end)
        (skip-chars-backward "\n\r" beg)
        (setq end (point)))
      (when (and (< beg end) (not (text-property-not-all beg end 'display nil)))
        (let ((display (propertize glyph 'face face)))
          (add-text-properties beg end
                               (list 'display display 'djot-modern--display display)))))))

(defun djot-modern--decorate (capture beg end)
  "Decorate CAPTURE, clipped to BEG and END."
  (let* ((tag (car capture)) (node (cdr capture))
         (start (max beg (treesit-node-start node)))
         (stop (min end (treesit-node-end node))))
    (when (< start stop)
      (pcase tag
        ((or 'heading 'heading-marker)
         (let ((heading node))
           (while (not (equal (treesit-node-type heading) "heading"))
             (setq heading (treesit-node-parent heading)))
           (let* ((marker (treesit-node-child heading 0 t))
                  (level (max 1 (min 4 (length (string-trim (treesit-node-text marker)))))))
             (if (eq tag 'heading)
                 (djot-modern--paint start stop (nth (1- level) djot-modern--faces))
               (djot-modern--paint start stop 'djot-modern-marker
                                   (aref ["◉ " "○ " "✳ " "· "] (1- level)))))))
        ('bullet (djot-modern--paint start stop 'djot-modern-marker "• "))
        ('unchecked (djot-modern--paint start stop 'djot-modern-marker "☐"))
        ('checked (djot-modern--paint start stop 'djot-modern-checked "☑"))
        ('quote (djot-modern--paint start stop 'djot-modern-marker "│ "))
        ('pipe (djot-modern--paint start stop 'djot-modern-marker "│"))
        ('rule (djot-modern--paint start stop 'djot-modern-marker "────────"))
        (_ (djot-modern--paint start stop
                              (intern (concat "djot-modern-" (symbol-name tag)))))))))

(defun djot-modern--match (limit)
  "Decorate parsed nodes between point and font-lock LIMIT.
Return nil: this matcher applies properties directly, without match data."
  (let ((beg (point)))
    (when (and djot-modern--active (< beg limit))
      (save-restriction
        (widen)
        (with-silent-modifications
          (djot-modern--clear beg limit)
          (when djot-modern--query
            (dolist (capture (treesit-query-capture
                             djot-modern--parser djot-modern--query beg limit))
              (djot-modern--decorate capture beg limit)))))))
  (goto-char limit)
  nil)

(defun djot-modern--changed (ranges parser)
  "Invalidate structural RANGES reported by PARSER.
Ordinary text edits are also handled by font-lock's normal change hooks."
  (when (and djot-modern--active (eq parser djot-modern--parser))
    (save-restriction
      (widen)
      (dolist (range ranges)
        (djot-modern--clear (car range) (cdr range))
        (font-lock-flush (car range) (cdr range))))))

(defun djot-modern--after-major-mode ()
  "Preserve base fontification when activated from a major mode hook."
  (remove-hook 'after-change-major-mode-hook #'djot-modern--after-major-mode t)
  ;; Global font-lock runs after major mode hooks.  Our early activation must
  ;; not take ownership of font-lock that the major mode would enable anyway.
  (when (and global-font-lock-mode font-lock-defaults
             (cond ((eq font-lock-global-modes t) t)
                   ((eq (car-safe font-lock-global-modes) 'not)
                    (not (memq major-mode (cdr font-lock-global-modes))))
                   (t (memq major-mode font-lock-global-modes))))
    (setq djot-modern--font-lock-was-enabled t)))

(defun djot-modern--disable ()
  "Release this buffer's decorations and parser resources."
  (when djot-modern--active
    (setq djot-modern--active nil)
    (remove-hook 'change-major-mode-hook #'djot-modern--before-major-mode t)
    (remove-hook 'after-change-major-mode-hook #'djot-modern--after-major-mode t)
    (remove-hook 'before-change-functions #'djot-modern--clear t)
    (remove-function (local 'filter-buffer-substring-function)
                     #'djot-modern--filter-substring)
    (treesit-parser-remove-notifier djot-modern--parser #'djot-modern--changed)
    (font-lock-remove-keywords nil djot-modern--keywords)
    (remove-function (local 'font-lock-unfontify-region-function) #'djot-modern--clear)
    (save-restriction
      (widen)
      (djot-modern--clear (point-min) (point-max))
      (font-lock-flush))
    (when djot-modern--owns-parser (treesit-parser-delete djot-modern--parser))
    (setq djot-modern--parser nil djot-modern--query nil djot-modern--owns-parser nil)
    (unless djot-modern--font-lock-was-enabled (font-lock-mode -1))))

(defun djot-modern--before-major-mode ()
  "Disable before changing major mode, while local state still exists."
  (djot-modern-mode -1))

;;;###autoload
(define-minor-mode djot-modern-mode
  "Display Djot with restrained typography and editable source.
Requires Emacs tree-sitter support and an installed tree-sitter-djot grammar.
Works with `text-mode' or a Djot major mode.  No text is changed.  Toggle
again to apply customization changes or to see the original source display."
  :lighter " DjM" :group 'djot-modern
  (if (not djot-modern-mode)
      (djot-modern--disable)
    (unless djot-modern--active
      (condition-case err
          (progn
            (unless (treesit-ready-p 'djot t)
              (user-error "Djot grammar unavailable; see djot-modern README.org"))
            ;; Compile before touching buffer state: incompatible grammars fail cleanly.
            (let* ((patterns (djot-modern--patterns))
                   (query (and patterns (treesit-query-compile 'djot patterns t)))
                   (existing (cl-find 'djot (treesit-parser-list)
                                      :key #'treesit-parser-language)))
              (setq djot-modern--query query
                    djot-modern--font-lock-was-enabled font-lock-mode
                    djot-modern--parser (or existing (treesit-parser-create 'djot))
                    djot-modern--owns-parser (not existing)
                    djot-modern--active t))
            (font-lock-add-keywords nil djot-modern--keywords 'append)
            (add-function :before (local 'font-lock-unfontify-region-function)
                          #'djot-modern--clear)
            ;; Deleted text must enter undo history without our decorations.
            (add-hook 'before-change-functions #'djot-modern--clear nil t)
            (add-function :filter-return (local 'filter-buffer-substring-function)
                          #'djot-modern--filter-substring)
            (treesit-parser-add-notifier djot-modern--parser #'djot-modern--changed)
            (add-hook 'change-major-mode-hook #'djot-modern--before-major-mode nil t)
            (add-hook 'after-change-major-mode-hook #'djot-modern--after-major-mode nil t)
            (font-lock-mode 1)
            (save-restriction (widen) (font-lock-flush)))
        (error
         (djot-modern--disable)
         (setq djot-modern-mode nil)
         (signal (car err) (cdr err)))))))

(provide 'djot-modern)
;;; djot-modern.el ends here
