;; Copyright (C) 2003-2008 Shawn Betts
;;
;;  This file is part of stumpwm.
;;
;; stumpwm is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; stumpwm is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this software; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
;; Boston, MA 02111-1307 USA

;; Commentary:
;;
;; Window Manager commands that users can use to manipulate stumpwm
;; and write custos.
;;
;; Code:

(in-package :stumpwm)

(export '(defprogram-shortcut
          pathname-is-executable-p
	  programs-in-path
	  restarts-menu
	  run-or-raise
	  run-shell-command
          window-send-string))

(defun restarts-menu (err)
  "Display a menu with the active restarts and let the user pick
one. Error is the error being recovered from. If the user aborts the
menu, the error is re-signalled."
  (let ((restart (select-from-menu (current-screen)
                                   (mapcar (lambda (r)
                                             (list (format nil "[~a] ~a"
                                                           (restart-name r)
                                                           (substitute #\Space
                                                                       #\Newline
                                                                       (write-to-string r :escape nil)))
                                                   r))
                                           ;; a crusty way to get only
                                           ;; the restarts from
                                           ;; stumpwm's top-level
                                           ;; restart inward.
                                           (reverse (member 'top-level
                                                            (reverse (compute-restarts))
                                                            :key 'restart-name)))
                                   (format nil "Error: ~a"
                                           (substitute #\Space
                                                       #\Newline
                                                       (write-to-string err :escape nil))))))
    (when restart
      (invoke-restart (second restart)))))

(defun banish-pointer (&optional (where *banish-pointer-to*))
  "Move the pointer to the lower right corner of the head, or
 WHEREever (one of :screen :head :frame or :window)"
  (let* ((screen (current-screen))
         (group (current-group))
         (head (current-head))
         (frame (tile-group-current-frame group))
         (window (frame-window frame))
         (x (1- (+ (frame-x frame) (frame-width frame))))
         (y (1- (+ (frame-display-y group frame) (frame-display-height group frame)))))
    (ecase where
      (:screen
       (setf x (1- (+ (screen-x screen) (screen-width screen)))
             y (1- (+ (screen-y screen) (screen-height screen)))))
      (:head
       (setf x (1- (+ (head-x head) (head-width head)))
             y (1- (+ (head-y head) (head-height head)))))
      (:frame)
      (:window
       (when window
         (let ((win (window-parent window)))
           (setf x (1- (+ (xlib:drawable-x win) (xlib:drawable-width win)))
                 y (1- (+ (xlib:drawable-y win) (xlib:drawable-height win))))))))
    (warp-pointer (group-screen group) x y)))

(defcommand banish (&optional where) (:rest)
  "Warp the mouse the lower right corner of the current head."
  (if where
      (banish-pointer (intern (string-upcase where) :keyword))
      (banish-pointer)))

(defcommand ratwarp (x y) ((:number "X: ") (:number "Y: "))
  "Warp the mouse to the specified location."
  (warp-pointer (current-screen) x y))

(defcommand ratrelwarp (dx dy) ((:number "Delta X: ") (:number "Delta Y: "))
  "Warp the mouse by the specified amount from its current position."
  (warp-pointer-relative dx dy))

(defcommand ratclick (&optional (button 1)) (:number)
  "Simulate a pointer button event at the current pointer
location. Note: this function rarely works."
  (when (current-window)
    (send-fake-click (current-window) button)))

(defun programs-in-path (&optional full-path (path (split-string (getenv "PATH") ":")))
  "Return a list of programs in the path that start with @var{base}. if
@var{full-path} is @var{t} then return the full path, otherwise just
return the filename. @var{path} is by default the @env{PATH}
evironment variable but can be specified. It should be a string containing
each directory seperated by a colon."
  (loop
   for p in path
   for dir = (probe-path p)
   when dir
   nconc (loop
          for file in (directory (merge-pathnames (make-pathname :name :wild) dir))
          for namestring = (file-namestring file)
	    when (pathname-is-executable-p file)
	    collect (if full-path
			(namestring file)
			namestring))))

(defstruct path-cache
  programs modification-dates paths)

(defvar *path-cache* nil
  "A cache containing the programs in the path, used for completion.")

(defun rehash (&optional (paths (mapcar 'parse-namestring (split-string (getenv "PATH") ":"))))
  "Update the cache of programs in the path stored in @var{*programs-list*} when needed."
  (let ((dates (mapcar (lambda (p)
                         (when (probe-path p)
                           (portable-file-write-date p)))
                       paths)))
    (finish-output)
    (unless (and *path-cache*
                 (equal (path-cache-paths *path-cache*) paths)
                 (equal (path-cache-modification-dates *path-cache*) dates))
      (setf *path-cache* (make-path-cache :programs (programs-in-path nil paths)
                                          :modification-dates dates
                                          :paths paths)))))

(defun complete-program (base)
  "return the list of programs in @var{*path-cache*} whose names begin
with base. Automagically update the cache."
  (rehash)
  (remove-if-not #'(lambda (p)
		     (when (<= (length base) (length p))
                       (string= base p
                                :end1 (length base)
                                :end2 (length base)))) (path-cache-programs *path-cache*)))

(defcommand run-shell-command (cmd &optional collect-output-p) ((:shell "/bin/sh -c "))
  "Run the specified shell command. If @var{collect-output-p} is @code{T}
then run the command synchonously and collect the output. Be
careful. If the shell command doesn't return, it will hang StumpWM. In
such a case, kill the shell command to resume StumpWM."
  (if collect-output-p
      (run-prog-collect-output *shell-program* "-c" cmd)
      (run-prog *shell-program* :args (list "-c" cmd) :wait nil)))

(defcommand-alias exec run-shell-command)

(defcommand eval-line (cmd) ((:rest "Eval: "))
  "Evaluate the s-expression and display the result(s)."
  (handler-case
      (message "^20~{~a~^~%~}"
               (mapcar 'prin1-to-string
                       (multiple-value-list (eval (read-from-string cmd)))))
    (error (c)
      (err "^B^1*~A" c))))

(defcommand-alias eval eval-line)

(defcommand echo (string) ((:rest "Echo: "))
  "Display @var{string} in the message bar."
  ;; The purpose of echo is always to pop up a message window.
  (let ((*executing-stumpwm-command* nil))
    (message "~a" string)))

(defun send-meta-key (screen key)
  "Send the key to the current window on the specified screen."
  (when (screen-current-window screen)
    (send-fake-key (screen-current-window screen) key)))

(defcommand meta (key) ((:key "Key: "))
"Send a fake key to the current window. @var{key} is a typical StumpWM key, like @kbd{C-M-o}."
  (send-meta-key (current-screen) key))

(defcommand loadrc () ()
"Reload the @file{~/.stumpwmrc} file."
  (handler-case
      (progn
        (with-restarts-menu (load-rc-file nil)))
    (error (c)
      (message "^1*^BError loading rc file: ^n~A" c))
    (:no-error (&rest args)
      (declare (ignore args))
      (message "rc file loaded successfully."))))

(defcommand keyboard-quit () ()
    ""
  ;; This way you can exit from command mode
  (when (pop-top-map)
    (message "Exited.")))

(defcommand-alias abort keyboard-quit)


(defcommand quit () ()
"Quit StumpWM."
  (throw :top-level :quit))

(defcommand soft-restart () ()
  "Soft Restart StumpWM. The lisp process isn't restarted. Instead,
control jumps to the very beginning of the stumpwm program. This
differs from a theoretical hard restart, which would restart the unix
process."
  (throw :top-level :restart))

(defun run-or-raise (cmd props &optional (all-groups *run-or-raise-all-groups*) (all-screens *run-or-raise-all-screens*))
  "Run the shell command, @var{cmd}, unless an existing window
matches @var{props}. @var{props} is a property list with the following keys:

@table @code
@item :class
Match the window's class.
@item :instance
Match the window's instance or resource-name.
@item :role
Match the window's @code{WM_WINDOW_ROLE}.
@item :title
Match the window's title.
@end table

By default, the global @var{*run-or-raise-all-groups*} decides whether
to search all groups or the current one for a running
instance. @var{all-groups} overrides this default. Similarily for
@var{*run-or-raise-all-screens*} and @var{all-screens}."
  (labels
      ;; Raise the window win and select its frame.  For now, it
      ;; does not select the screen.
      ((goto-win (win)
         (let* ((group (window-group win))
                (frame (window-frame win))
                (old-frame (tile-group-current-frame group)))
           (frame-raise-window group frame win)
           (focus-all win)
           (unless (eq frame old-frame)
             (show-frame-indicator group))))
       (sort-windows-by-group (winlist)
         (stable-sort (sort winlist #'< :key #'window-number)
                      #'< :key #'(lambda (w) (group-number (window-group w)))))
       (find-window (winlist)
         (let* ((match (remove-if-not #'(lambda (w)
                                          (apply 'window-matches-properties-p w props))
                                      winlist))
                (match-sorted (sort-windows-by-group match))
                (rest (member (current-window) match-sorted)))
           (if (<= (length rest) 1) ; current win not a match or no matches left
               (car match-sorted)
               (cadr rest)))))
    (let* ((screens (if all-screens
                        *screen-list*
                        (list (current-screen))))
           (winlist (if all-groups
                        (mapcan (lambda (s) (screen-windows s)) screens)
                        (group-windows (current-group))))
           (win (find-window winlist)))
      (if win
          (goto-win win)
          (run-shell-command cmd)))))

(defcommand reload () ()
"Reload StumpWM using @code{asdf}."
  (message "Reloading StumpWM...")
  #+asdf (with-restarts-menu
             (asdf:operate 'asdf:load-op :stumpwm))
  #-asdf (message "^B^1*Sorry, StumpWM can only be reloaded with asdf (for now.)")
  #+asdf (message "Reloading StumpWM...^B^2*Done^n."))

(defcommand emacs () ()
  "Start emacs unless it is already running, in which case focus it."
  (run-or-raise "emacs" '(:class "Emacs")))

(defcommand copy-unhandled-error () ()
  "When an unhandled error occurs, StumpWM restarts and attempts to
continue. Unhandled errors should be reported to the mailing list so
they can be fixed. Use this command to copy the unhandled error and
backtrace to the X11 selection so you can paste in your email when
submitting the bug report."
  (if *last-unhandled-error*
      (progn
        (set-x-selection (format nil "~a~%~a" (first *last-unhandled-error*) (second *last-unhandled-error*)))
        (message "Copied to clipboard."))
      (message "There was no unhandled error!")))

(defmacro defprogram-shortcut (name &key (command (string-downcase (string name)))
                                         (props `'(:class ,(string-capitalize command)))
                                         (map *top-map*)
                                         (key (kbd (concat "H-" (subseq command 0 1)))))
  "define a command and key binding to run or raise a program."
  `(progn
     (defcommand ,name () ()
       (run-or-raise ,command ,props))
     (define-key ,map ,key ,(string-downcase (string name)))))

(defcommand show-window-properties () ()
  "Shows the properties of the current window. These properties can be
used for matching windows with run-or-raise or window placement
rules."
  (let ((w (current-window)))
    (message-no-timeout "class: ~A~%instance: ~A~%type: :~A~%role: ~A~%title: ~A"
                        (window-class w)
                        (window-res w)
                        (string (window-type w))
                        (window-role w)
                        (window-title w))))

(defcommand list-window-properties () ()
  "List all the properties of the current window and their values,
like xprop."
  (message-no-timeout
   "~{~30a: ~a~^~%~}"
   (let ((win (if (current-window)
                  (window-xwin (current-window))
                  (screen-root (current-screen)))))
     (loop for i in (xlib:list-properties win)
        collect i
        collect (multiple-value-bind (values type)
                    (xlib:get-property win i)
                  (case type
                    (:wm_state (format nil "~{~a~^, ~}"
                                       (loop for v in values
                                          collect (case v (0 "Iconic") (1 "Normal") (2 "Withdrawn") (t "Unknown")))))
                    (:window i)
                    ;; _NET_WM_ICON is huuuuuge
                    (:cardinal (if (> (length values) 20)
                                   (format nil "~{~d~^, ~}..." (subseq values 0 15))
                                   (format nil "~{~d~^, ~}" values)))
                    (:atom (format nil "~{~a~^, ~}"
                                   (mapcar (lambda (v) (xlib:atom-name *display* v)) values)))
                    (:string (format nil "~{~s~^, ~}"
                                     (mapcar (lambda (x) (coerce (mapcar 'xlib:card8->char x) 'string))
                                             (split-seq values '(0)))))
                    (:utf8_string (format nil "~{~s~^, ~}"
                                          (mapcar 'utf8-to-string
                                                  (split-seq values '(0)))))
                    (t values))))))))
