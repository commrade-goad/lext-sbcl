;;;; build.lisp - Compiler script for LExt Template Engine
(in-package :cl-user)

(declaim (optimize (speed 3) (safety 1) (space 0) (debug 0)))

(format t "Starting optimized build of LExt...~%")

;; Push the build feature to prevent auto-running main in lext.lisp
(pushnew :lext-build *features*)

;; Compile and load the files
(handler-bind ((warning #'muffle-warning))
  (format t "Compiling standard library (basic.lisp)...~%")
  (load (compile-file "basic.lisp"))
  (format t "Compiling template lext (lext.lisp)...~%")
  (load (compile-file "lext.lisp")))

;; Clean up intermediate compilation artifacts
(format t "Cleaning up intermediate build files...~%")
(ignore-errors
 (delete-file "basic.fasl")
 (delete-file "lext.fasl"))

;; Save the optimized standalone binary executable
(format t "Saving executable 'lext'...~%")
(sb-ext:save-lisp-and-die "lext"
                          :executable t
                          :toplevel #'main)
