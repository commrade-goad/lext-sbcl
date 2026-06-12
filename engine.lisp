;;;; engine.lisp - High-Performance Template Renderer for SBCL Matrix Engine
(in-package :cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (load "basic.lisp"))

(defun handle-lisp-tag (file-stream)
  "Triggered when @@ is found. Uses CL's native reader to parse and evaluate the next form."
  (handler-case
      (let* ((lisp-form (read file-stream)) ; Automatically parses the entire matched form safely!
             (evaluation-result
               (cond
                 ;; Edge-case Handler: If the user wrote a single variable wrapped in parens, e.g. (*user-name*),
                 ;; evaluate it as a standalone symbol value instead of trying to call it as a function.
                 ((and (consp lisp-form)
                       (null (cdr lisp-form))
                       (symbolp (car lisp-form))
                       (boundp (car lisp-form))
                       (not (fboundp (car lisp-form))))
                  (symbol-value (car lisp-form)))

                 ;; Otherwise, execute the form natively
                 (t (eval lisp-form)))))

        ;; Silence top-level definitions and structural assignments
        (if (and (consp lisp-form)
                 (member (car lisp-form) '(defun defparameter defvar setf setq declaim proclaim define defmacro progn eval-when load require)))
            ""
            (if (null evaluation-result) "" (princ-to-string evaluation-result))))
    (error (e)
      (format nil "~C[1;31m[Template Error: ~A]~C[0m" #\Esc e #\Esc))))

(defun render-template (filename)
  "Reads a template file character-by-character and delegates code blocks to the reader."
  (with-output-to-string (output-buffer)
    (let ((*standard-output* output-buffer))
      (with-open-file (file-stream filename :direction :input :if-does-not-exist :error)
        (loop for char = (read-char file-stream nil nil)
              while char
              do (cond
                   ;; When we hit @@, pass control directly to the native Lisp reader
                   ((and (char= char #\@)
                         (char= (peek-char nil file-stream nil nil) #\@))
                    (read-char file-stream) ; Eat the second '@'
                    (let ((rendered-tag (handle-lisp-tag file-stream)))
                      (if (string= rendered-tag "")
                          ;; Clean up trailing layout newlines left by hidden definitions
                          (let ((next-c (peek-char nil file-stream nil nil)))
                            (cond
                              ((and next-c (char= next-c #\Newline))
                               (read-char file-stream))
                              ((and next-c (char= next-c #\Return))
                               (read-char file-stream) ; Eat '\r'
                               (let ((next-next-c (peek-char nil file-stream nil nil)))
                                 (when (and next-next-c (char= next-next-c #\Newline))
                                   (read-char file-stream))))))
                          (write-string rendered-tag output-buffer))))

                   ;; Route normal HTML characters straight to our output buffer
                   (t (write-char char output-buffer))))))))

;; --- Command Line Execution & Premium UI/UX ---

(defun find-basic-lisp ()
  (let ((path1 (merge-pathnames "basic.lisp" sb-ext:*runtime-pathname*))
        (path2 (merge-pathnames "basic.lisp" *default-pathname-defaults*)))
    (cond
      ((probe-file path1) path1)
      ((probe-file path2) path2)
      (t nil))))

(defun print-help ()
  (format *error-output* "~C[1;36mLExt Template Engine~C[0m - High-Performance SBCL template renderer~%" #\Esc #\Esc)
  (format *error-output* "~%~C[1mUSAGE:~C[0m~%" #\Esc #\Esc)
  (format *error-output* "  lext <input-file> [output-file]~%")
  (format *error-output* "  lext -s/--script <script-file>~%")
  (format *error-output* "  lext -h/--help~%")
  (format *error-output* "  lext -v/--version~%")
  (format *error-output* "~%~C[1mOPTIONS:~C[0m~%" #\Esc #\Esc)
  (format *error-output* "  ~C[32m<input-file>~C[0m        The template HTML/text file to render @@ forms.~%" #\Esc #\Esc)
  (format *error-output* "  ~C[32m[output-file]~C[0m       (Optional) File path to write the output. Defaults to stdout.~%" #\Esc #\Esc)
  (format *error-output* "  ~C[32m-s, --script~C[0m       Run <script-file> via SBCL with LExt standard library preloaded.~%" #\Esc #\Esc)
  (format *error-output* "  ~C[32m-h, --help~C[0m         Show this help information.~%" #\Esc #\Esc)
  (format *error-output* "  ~C[32m-v, --version~C[0m      Show LExt version information.~%~%" #\Esc #\Esc))

(defun main ()
  (let* ((args sb-ext:*posix-argv*)
         ;; The first element is the script/executable name, the rest are user args
         (user-args (cdr args))
         (first-arg (first user-args)))
    (cond
      ;; Help flag
      ((member first-arg '("-h" "--help") :test #'string=)
       (print-help)
       (sb-ext:exit :code 0))
      
      ;; Version flag
      ((member first-arg '("-v" "--version") :test #'string=)
       (format *error-output* "~C[1;36mLExt~C[0m version 1.1.0~%" #\Esc #\Esc)
       (sb-ext:exit :code 0))
      
      ;; Script flag
      ((member first-arg '("-s" "--script") :test #'string=)
       (let ((script-path (second user-args)))
         (if script-path
             (let ((basic-path (find-basic-lisp)))
               (if basic-path
                   (let ((process (sb-ext:run-program "sbcl"
                                                      (list "--load" (namestring basic-path)
                                                            "--script" script-path)
                                                      :search t
                                                      :output *standard-output*
                                                      :error *error-output*
                                                      :input *standard-input*)))
                     (if process
                         (sb-ext:exit :code (sb-ext:process-exit-code process))
                         (progn
                           (format *error-output* "~C[1;31m[Error]~C[0m Failed to launch sbcl.~%" #\Esc #\Esc)
                           (sb-ext:exit :code 1))))
                   (progn
                     (format *error-output* "~C[1;31m[Error]~C[0m Could not locate basic.lisp.~%" #\Esc #\Esc)
                     (sb-ext:exit :code 1))))
             (progn
               (format *error-output* "~C[1;31m[Error]~C[0m No script file specified.~%~%" #\Esc #\Esc)
               (print-help)
               (sb-ext:exit :code 1)))))
      
      ;; Unknown option check
      ((and first-arg (char= (char first-arg 0) #\-))
       (format *error-output* "~C[1;31m[Error]~C[0m Unknown option: ~A~%~%" #\Esc #\Esc first-arg)
       (print-help)
       (sb-ext:exit :code 1))
      
      ;; File rendering
      (first-arg
       (let ((input-file first-arg)
             (output-file (second user-args)))
         (if output-file
             (handler-case
                 (let ((result (render-template input-file)))
                   (with-open-file (out-stream output-file
                                               :direction :output
                                               :if-exists :supersede
                                               :if-does-not-exist :create)
                     (write-string result out-stream))
                   (format *error-output* "~C[1;32m[Success]~C[0m Rendered ~A to ~A~%" #\Esc #\Esc input-file output-file)
                   (sb-ext:exit :code 0))
               (error (e)
                 (format *error-output* "~C[1;31m[Error]~C[0m Failed to render: ~A~%" #\Esc #\Esc e)
                 (sb-ext:exit :code 1)))
             (handler-case
                 (let ((result (render-template input-file)))
                   (write-string result)
                   (finish-output)
                   (sb-ext:exit :code 0))
               (error (e)
                 (format *error-output* "~C[1;31m[Error]~C[0m Failed to render: ~A~%" #\Esc #\Esc e)
                 (sb-ext:exit :code 1))))))
      
      ;; No arguments
      (t
       (print-help)
       (sb-ext:exit :code 1)))))

(unless (member :lext-build *features*)
  (main))
