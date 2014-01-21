;;; lispy-inline.el --- inline arglist and documentation.

;; Copyright (C) 2014 Oleh Krehel

;; Author: Oleh Krehel <ohwoeowho@gmail.com>
;; URL: https://github.com/abo-abo/lispy
;; Version: 0.3
;; Keywords: lisp

;; This file is not part of GNU Emacs

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Display current function arguments or docstring in an in-place
;; overlay.

;;; Code:

(defgroup lispy-faces nil
  "Font-lock faces for `lispy'."
  :group 'lispy
  :prefix "lispy-face-")

(defface lispy-face-hint
  '((t (:background "#fff3bc" :foreground "black")))
  "Basic hint face."
  :group 'lispy-faces)

(defface lispy-face-req-nosel
    '((t (:inherit lispy-face-hint)))
  "Face for required unselected args."
  :group 'lispy-faces)

(defface lispy-face-req-sel
    '((t (:inherit lispy-face-req-nosel :bold t)))
  "Face for required selected args."
  :group 'lispy-faces)

(defface lispy-face-opt-nosel
    '((t (:inherit lispy-face-hint :foreground "#666666" :slant italic)))
  "Face for optional unselected args."
  :group 'lispy-faces)

(defface lispy-face-opt-sel
    '((t (:inherit lispy-face-opt-nosel :bold t)))
  "Face for optional selected args."
  :group 'lispy-faces)

(defface lispy-face-rst-nosel
    '((t (:inherit lispy-face-hint)))
  "Face for rest unselected args."
  :group 'lispy-faces)

(defface lispy-face-rst-sel
    '((t (:inherit lispy-face-rst-nosel :bold t)))
  "Face for rest selected args."
  :group 'lispy-faces)

(defvar lispy-overlay nil
  "Hint overlay instance.")

(defvar lispy-hint-pos nil
  "Point position where the hint should be (re-) displayed.")

;; ——— Commands ————————————————————————————————————————————————————————————————
(defun lispy-arglist-inline ()
  "Display arglist for `lispy--current-function' inline."
  (interactive)
  (let (deleted)
    (when (overlayp lispy-overlay)
      (delete-overlay lispy-overlay)
      (setq lispy-overlay nil)
      (setq deleted t))
    (save-excursion
      (unless (looking-at "(")
        (lispy-out-backward 1))
      (when (or (not deleted) (not (= lispy-hint-pos (point))))
        (if (memq major-mode '(emacs-lisp-mode lisp-interaction-mode))
            (let ((sym (lispy--current-function)))
              (cond ((fboundp sym)
                     (setq lispy-hint-pos (point))
                     (lispy--show (lispy--pretty-args sym)))))
          (error "Only elisp is supported currently."))))))

(defun lispy-describe-inline ()
  "Display documentation for `lispy--current-function' inline."
  (interactive)
  (let ((deleted))
    (when (overlayp lispy-overlay)
      (delete-overlay lispy-overlay)
      (setq lispy-overlay nil)
      (setq deleted t))
    (save-excursion
      (unless (looking-at "(")
        (lispy-out-backward 1))
      (when (or (not deleted) (not (= lispy-hint-pos (point))))
        (cond ((memq major-mode '(emacs-lisp-mode lisp-interaction-mode))
               (let ((sym (lispy--current-function)))
                 (cond ((fboundp sym)
                        (setq lispy-hint-pos (point))
                        (or (lispy--show (propertize (documentation sym)
                                                 'face 'lispy-face-hint))
                            (describe-function sym))))))
              ((eq major-mode 'clojure-mode)
               (nrepl-doc-handler (lispy--current-function)))
              (t
               (error "Only elisp is supported currently.")))))))

;; ——— Utilities ———————————————————————————————————————————————————————————————
(defun lispy--arglist (symbol)
  "Get arglist for SYMBOL."
  (let (doc)
    (if (setq doc (help-split-fundoc (documentation symbol t) symbol))
        (car doc)
      (prin1-to-string
       (cons symbol (help-function-arglist symbol))))))

(defun lispy--join-pad (strs width)
  "Join STRS padding each line with WIDTH spaces."
  (let ((padding (make-string width ?\ )))
    (mapconcat (lambda(x) (concat padding x))
               strs
               "\n")))

(defun lispy--show (str)
  "Show STR hint.
Return t if window is large enough to display STR whole.
Otherwise don't do anything and return nil."
  (let ((strs (split-string str "\n")))
    (if (> (length strs) (window-height))
        nil
      (setq str (lispy--join-pad
                 strs
                 (string-width (buffer-substring
                                (line-beginning-position)
                                (point)))))
      (save-excursion
        (goto-char lispy-hint-pos)
        (forward-line -1)
        (end-of-line)
        (setq str (concat "\n" str (make-string 1 (char-after))))
        (font-lock-unfontify-region (point) (+ (point) 1))
        (if lispy-overlay
            (progn
              (move-overlay lispy-overlay (point) (+ (point) 1))
              (overlay-put lispy-overlay 'invisible nil))
          (setq lispy-overlay (make-overlay (point) (+ (point) 1)))
          (overlay-put lispy-overlay 'priority 9999))
        (overlay-put lispy-overlay 'display str)
        (overlay-put lispy-overlay 'after-string ""))
      t)))

(defun lispy--pretty-args (symbol)
  "Return a vector of fontified strings for function SYMBOL."
  (let* ((args (cdr (split-string (lispy--arglist symbol) "[( )]" t)))
         (p-opt (position "&optional" args :test 'equal))
         (p-rst (position "&rest" args :test 'equal))
         (a-req (subseq args 0 (or p-opt p-rst (length args))))
         (a-opt (and p-opt (subseq args (1+ p-opt) (or p-rst (length args)))))
         (a-rst (and p-rst (last args))))
    (format
     "(%s)"
     (mapconcat
      #'identity
      (append
       (list (propertize (symbol-name symbol) 'face 'lispy-face-hint))
       (mapcar (lambda(x) (propertize (downcase x)
                                 'face 'lispy-face-req-nosel)) a-req)
       (mapcar (lambda(x) (propertize (downcase x)
                                 'face 'lispy-face-opt-nosel)) a-opt)
       (mapcar (lambda(x) (propertize (concat (downcase x) "...")
                                 'face 'lispy-face-rst-nosel)) a-rst))
      " "))))

(provide 'lispy-inline)

;;; Local Variables:
;;; outline-regexp: ";; ———"
;;; End:

;;; lispy-inline.el ends here
