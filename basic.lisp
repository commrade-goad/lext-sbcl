;;;; basic.lisp - Elite, High-Performance FFI & Dev Stdlib for SBCL Engine Matrix
(in-package :cl-user)

;; =========================================================================
;; 1. Scheme-ish Compatibility & Ergonomics Layer
;; =========================================================================

(set-dispatch-macro-character #\# #\f (lambda (s c sub) (declare (ignore s c sub)) nil))
(set-dispatch-macro-character #\# #t (lambda (s c sub) (declare (ignore s c sub)) t))

(defmacro define (name value) `(defparameter ,name ,value))
(defmacro fn (args &body body)  `(lambda ,args ,@body))

(defun display (msg)
  (format t "~A~%" msg)
  (finish-output))

;; =========================================================================
;; 2. Low-Level POSIX System Call Bindings (The Redirection Sub-Engine)
;; =========================================================================

(sb-alien:define-alien-routine "fflush" sb-alien:int (stream (* sb-alien:void)))
(sb-alien:define-alien-routine "dup" sb-alien:int (oldfd sb-alien:int))
(sb-alien:define-alien-routine "dup2" sb-alien:int (oldfd sb-alien:int) (newfd sb-alien:int))
(sb-alien:define-alien-routine "close" sb-alien:int (fd sb-alien:int))
(sb-alien:define-alien-routine "tmpfile" (* sb-alien:void))
(sb-alien:define-alien-routine "fileno" sb-alien:int (stream (* sb-alien:void)))
(sb-alien:define-alien-routine "rewind" sb-alien:void (stream (* sb-alien:void)))
(sb-alien:define-alien-routine "fclose" sb-alien:int (stream (* sb-alien:void)))
(sb-alien:define-alien-routine "fgetc" sb-alien:int (stream (* sb-alien:void)))

;; =========================================================================
;; 3. Universal Capture Sandbox
;; =========================================================================

(defmacro capture (&body body)
  "Evaluates any code block while intercepting all C/POSIX stdout writes,
   returning them cleanly as a native Lisp string. Uses an auto-deleting
   tmpfs-backed file stream to handle infinite output sizes without blocking."
  (let ((g-saved (gensym "SAVED"))
        (g-tmp (gensym "TMP"))
        (g-fd (gensym "FD"))
        (g-str (gensym "STR"))
        (g-char (gensym "CHAR"))
        (null-ptr `(sb-alien:cast nil (* sb-alien:void))))
    `(progn
       (fflush ,null-ptr)                       ; Flush all current streams
       (let* ((,g-saved (dup 1))                ; Duplicate original stdout descriptor
              (,g-tmp (tmpfile))                ; Open safe, anonymous scratch file
              (,g-fd (fileno ,g-tmp)))
         (dup2 ,g-fd 1)                         ; Swap stdout descriptor to point to temp file
         (unwind-protect
              (progn ,@body)                    ; Execute inner payload logic
           (fflush ,null-ptr)                   ; Force all C modifications out to disk layout
           (dup2 ,g-saved 1)                    ; Restore terminal stdout immediately
           (close ,g-saved))                    ; Release tracking pointer descriptor
         (rewind ,g-tmp)                        ; Seek to beginning of captured byte data
         (let ((,g-str (with-output-to-string (s)
                         (loop for ,g-char = (fgetc ,g-tmp)
                               until (= ,g-char -1)
                               do (write-char (code-char ,g-char) s)))))
           (fclose ,g-tmp)                      ; Closes stream and auto-purges underlying disk file
           ,g-str)))))                          ; Ship native string output back to caller

;; =========================================================================
;; 4. Core Type Translator Matrix
;; =========================================================================

(defun translate-ffi-type (type)
  (case type
    (double 'sb-alien:double-float)
    (float  'sb-alien:single-float)
    (int    'sb-alien:int)
    (long   'sb-alien:long)
    (string 'sb-alien:c-string)
    (void   'sb-alien:void)
    (char   'sb-alien:char)
    (pointer '(* sb-alien:void))
    (t type)))

;; =========================================================================
;; 5. Memory Management & Vector Struct Packagers
;; =========================================================================

(defmacro with-alloc ((var type &optional (count 1)) &body body)
  "Allocates a strict hardware-stack tracking array frame. Automatically freed on block exit."
  `(sb-alien:with-alien ((,var (sb-alien:array ,(translate-ffi-type type) ,count)))
     ,@body))

(defmacro with-c-array ((var type lisp-list) &body body)
  "Transforms a dynamic Lisp list of numbers into a contiguous native C vector array.
   Ensures absolute cleanup protection via unwind blocks with zero memory leaks."
  (let ((g-list (gensym "LIST"))
        (g-len (gensym "LEN"))
        (g-idx (gensym "IDX"))
        (alien-type (translate-ffi-type type)))
    `(let* ((,g-list ,lisp-list)
            (,g-len (length ,g-list)))
       (let ((,var (sb-alien:make-alien (sb-alien:array ,alien-type 1) ,g-len)))
         (unwind-protect
              (progn
                (loop for ,g-idx from 0 for item in ,g-list
                      do (setf (sb-alien:deref ,var ,g-idx) item))
                ,@body)
           (sb-alien:free-alien ,var))))))

(defmacro with-c-string-array ((var lisp-string-list) &body body)
  "Converts a list of Lisp strings into a native null-terminated (char** ) block vector.
   Crucial for calling custom CLI tools, parsing arguments, or feeding layouts to C kernels."
  (let ((g-list (gensym "LIST"))
        (g-len (gensym "LEN"))
        (g-idx (gensym "IDX")))
    `(let* ((,g-list ,lisp-string-list)
            (,g-len (length ,g-list)))
       (let ((,var (sb-alien:make-alien (* sb-alien:c-string) (1+ ,g-len))))
         (unwind-protect
              (progn
                (loop for ,g-idx from 0 for str in ,g-list
                      do (setf (sb-alien:deref ,var ,g-idx) str))
                (setf (sb-alien:deref ,var ,g-len) nil) ; Enforce trailing NULL indicator
                ,@body)
           (sb-alien:free-alien ,var))))))

(defmacro ptr+ (sap-pointer byte-offset)
  "Low-overhead native hardware address math offset calculations."
  `(sb-sys:sap+ (sb-alien:alien-sap ,sap-pointer) ,byte-offset))

;; =========================================================================
;; 6. High-Level Struct Declarator
;; =========================================================================

(defmacro define-c-struct (name &rest fields)
  `(sb-alien:define-alien-type ,name
     (sb-alien:struct nil
       ,@(loop for (f-name f-type) in fields
               collect (list f-name (translate-ffi-type f-type))))))

;; =========================================================================
;; 7. Orthogonal Function Importer Engine
;; =========================================================================

(defun parse-printf-specifiers (fmt-str)
  (let ((types '()) (i 0) (len (length fmt-str)))
    (loop while (< i len)
          do (if (char= (char fmt-str i) #\%)
                 (progn
                   (incf i)
                   (if (and (< i len) (char= (char fmt-str i) #\%))
                       (incf i)
                       (progn
                         (loop while (and (< i len) (not (member (char fmt-str i) '(#\d #\i #\f #\s #\c #\x #\p))))
                               do (incf i))
                         (when (< i len)
                           (push (case (char fmt-str i)
                                   ((#\d #\i #\c #\x) 'sb-alien:int)
                                   (#\f 'sb-alien:double-float)
                                   (#\s 'sb-alien:c-string)
                                   (t 'sb-alien:int))
                                 types)
                           (incf i)))))
                 (incf i)))
    (nreverse types)))

(defun ffi-open (lib-path)
  (when (and lib-path (stringp lib-path))
    (sb-alien:load-shared-object lib-path))
  lib-path)

(defmacro c-import (name library c-name return-type arg-types &optional variadic-p)
  (declare (ignore library))
  (let ((real-return (translate-ffi-type return-type))
        (real-fixed-args (mapcar #'translate-ffi-type arg-types)))
    (if (not variadic-p)
        ;; Case A: Clean Uniform Static Routine Binding
        `(sb-alien:define-alien-routine (,c-name ,name) ,real-return
           ,@(loop for type in real-fixed-args for idx from 1
                  collect (list (intern (format nil "ARG~A" idx)) type)))
        ;; Case B: Universal Dynamic Stack-Frame Caller
        `(defmacro ,name (fmt-arg &rest dynamic-args)
           (let* ((inferred-types (if (stringp fmt-arg)
                                      (parse-printf-specifiers fmt-arg)
                                      (mapcar (lambda (a) (declare (ignore a)) 'sb-alien:int) dynamic-args)))
                  (all-arg-types (append ',real-fixed-args inferred-types))
                  (func-sig `(sb-alien:function ,',real-return ,@all-arg-types)))
             `(sb-alien:alien-funcall
               (sb-alien:extern-alien ,,c-name (sb-alien:function ,',real-return ,@all-arg-types))
               ,fmt-arg
               ,@dynamic-args))))))
