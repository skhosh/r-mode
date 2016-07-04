;;; r-mode.el --- Major mode for editing R code -*- lexical-binding: t; -*-
;; 
;; Copyright © 2016 Vitalie Spinu, Lionel Henry
;;
;; Authors: Vitalie Spinu <spinuvit@gmail.com>
;;          Lionel Henry <lionel.hry@gmail.com>
;; URL: http://github.com/r-emacs/r-mode
;; Keywords: languages R
;; Version: 0.1.0
;; Package-Requires: ((emacs "24.3"))
;; 
;; This file is not part of GNU Emacs.
;; 
;;; License:
;; 
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.
;;
;;; Commentary:
;;; 
;;; Code:

(require 'cl-lib)
(require 'imenu)
(require 'r-font-lock)
(require 'r-syntax)
(require 'r-indent)
(require 'r-roxy)

(defgroup r nil
  "Tools for editing R code."
  :prefix "r-"
  :group 'languages
  :link '(url-link :tag "Github" "https://github.com/r-emacs/r-mode")
  :link '(emacs-commentary-link :tag "Commentary" "r-mode"))

(defconst r-mode-version "0.1.0"
  "The current version of `r-mode'.")

(defvar r-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?\\ "\\" table) ; character quote
    (modify-syntax-entry ?\' "\"" table) ; string delimiter
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?`  "\"" table)
    (modify-syntax-entry ?%  "\"" table)
    (modify-syntax-entry ?#  "<"  table) ; open comment
    (modify-syntax-entry ?\n ">"  table) ; close comment
    (modify-syntax-entry ?$  "_"  table) ; symbol  
    (modify-syntax-entry ?.  "_"  table)
    (modify-syntax-entry ?:  "_"  table)
    (modify-syntax-entry ?@  "_"  table)
    (modify-syntax-entry ?_  "_"  table)
    (modify-syntax-entry ?&  "."  table)
    (modify-syntax-entry ?*  "."  table)
    (modify-syntax-entry ?+  "."  table)
    (modify-syntax-entry ?-  "."  table)
    (modify-syntax-entry ?/  "."  table)
    (modify-syntax-entry ?<  "."  table)
    (modify-syntax-entry ?<  "."  table)
    (modify-syntax-entry ?=  "."  table)
    (modify-syntax-entry ?>  "."  table)
    (modify-syntax-entry ?>  "."  table)
    (modify-syntax-entry ?|  "."  table)
    table)
  "Syntax table for R code.")

(defvar r-refactor-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "t") #'r-fix-T-F)
    (define-key map (kbd "SPC") #'r-align)))

(defvar r-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-r") 'r-refactor-map)
    (define-key map (kbd "C-c SPC") 'r-align)

    (easy-menu-define r-mode-menu map "R Mode Menu"
      '("R"
        ["Align expressions" r-align]
        ("Refactor"
         ["Align on ="  r-align]
         ["Fix T and F" r-fix-T-F])
        ("Font Lock"
         :filter r--generate-font-lock-submenu)
        "--"
        ["r-mode version" r-mode-display-version]))
    map)
  "Keymap for `r-mode'.")

;; adapted from ESS (needs more polishing)
(defvar r-imenu-generic-expression
  '(("Functions" "^\\(.+\\)[ \t\n]*<-[ \t\n]*function[ ]*(" 1)
    ("Classes" "^.*setClass(\\(.*\\)," 1)
    ("Coercions" "^.*setAs(\\([^,]+,[^,]*\\)," 1) ; show from and to
    ("Generics" "^.*setGeneric(\\([^,]*\\)," 1)
    ("Methods" "^.*set\\(Group\\|Replace\\)?Method(\\([^,]+,[^,]*\\)" 2)
    ;;[ ]*\\(signature=\\)?(\\(.*,?\\)*\\)," 1)
    ;;("Other" "^\\(.+\\)\\s-*<-[ \t\n]*[^\\(function\\|read\\|.*data\.frame\\)]" 1)
    ("Package" "^.*\\(library\\|require\\)(\\(.*\\)" 2)
    ("Data" "^\\(.+\\)[ \t\n]-*<-[ \t\n]*\\(read\\|.*data\.frame\\).*(" 1)))

(defvar r-prettify-symbols-alist
  ;; probably it's not worth making this a defcustom
  '(("<-" . ?←)
    ("<<-" . ?↞)
    ("->" . ?→)
    ("->>" . ?↠))
  "Value used for `prettify-symbols-alist'")

(defvar r-mode-variables
  '(
    ;; IMENU
    (imenu-generic-expression . r-imenu-generic-expression)

    ;; COMMENTS 
    (comment-add        . (if r-indent-with-fancy-comments 1 0)) ; ## or # for comment-region
    (comment-column     . 40)               
    (comment-use-syntax . t)
    (comment-start      . "#")
    (comment-start-skip . "#+'? *")     ; support roxygen blocks

    ;; OUTLINE
    (outline-regexp . "#+ .* ---+")     ; same as R-studio sections 
    (outline-level  . #'r--outline-level)

    ;; PARAGRAPHS
    (paragraph-start    . (concat "\\(" comment-start-skip "\\)*" paragraph-start))
    (paragraph-separate . (concat "\\(" comment-start-skip "\\)*" paragraph-separate))

    ;; FILLING
    (fill-paragraph-function   . #'r-fill-paragraph)
    (fill-nobreak-predicate    . #'r-within-string-p)
    (adaptive-fill-function    . #'r-roxy-adaptive-fill-function)

    ;; INDENTATION
    (indent-tabs-mode . nil)
    (indent-line-function   . #'r-indent-line)
    ;; (indent-region-function . #'r-indent-region)
    (prettify-symbols-alist . r-prettify-symbols-alist)
    )
  "Buffer local variables for R mode.
The variables are initialized in reversed order. Thus, you can
use `push' or `add-to-list' to overwrite the variable.")

(defun r--outline-level ()
  "Function used as `outline-level' in `r-mode'."
  (when (looking-at "#+")
    (length (match-string 0))))

(defun r--set-local-variables (alist)
  "Set local variables from ALIST in current buffer"
  (mapcar (lambda (pair)
            (make-local-variable (car pair))
            (set (car pair) (eval (cdr pair))))
          (reverse alist)))

;;;###autoload
(define-derived-mode r-mode prog-mode "R"
  "Major mode for editing R code.
\\{r-mode-map}"
  :group 'r
  (r--set-local-variables r-mode-variables)
  (setq r-font-lock-keywords (r--extract-fl-keywords))
  (add-to-list 'completion-at-point-functions 'r-roxy-tag-completion)
  (setq font-lock-defaults
        `(r-font-lock-keywords
          nil nil nil
          (font-lock-syntactic-face-function . r-font-lock-syntactic-face-function))))

;;;###autoload
(defun r-mode-display-version ()
  "Display the current `r-mode-version' in the minibuffer."
  (interactive)
  (message "r-mode (version %s)" r-mode-version))


;;; Refactor
;; tothink: should these functions apply to a buffer or paragraph or top form?
(defun r-fix-T-F (&optional beg end)
  "Fix T/F into TRUE and FALSE except for in comments and strings.
If BEG and END are nil, use the region if active, otherwise fix
in the whole buffer."
  (interactive "r")
  beg end
  (error "Not implemented yet")
  ;; see of how to get 
  ;; (save-excursion
  ;;   (goto-char from)
  ;;   (ess-rep-regexp "\\(\\([][=,()]\\|<-\\) *\\)T\\>" "\\1TRUE"
  ;;                   'fixcase nil t)
  ;;   (goto-char from)
  ;;   (ess-rep-regexp "\\(\\([][=,()]\\|<-\\) *\\)F\\>" "\\1FALSE"
  ;;                   'fixcase nil (not quietly)))
  )

(defun r-align ()
  "Align declarations and function calls on =."
  (interactive)
  (error "Not implemented yet."))


;;; Filling

(provide 'r-mode)
;;; r-mode.el ends here