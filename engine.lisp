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

(defun print-help ()
  (format *error-output* "~C[1;36mLExt Template Engine~C[0m - High-Performance SBCL template renderer~%" #\Esc #\Esc)
  (format *error-output* "~%~C[1mUSAGE:~C[0m~%" #\Esc #\Esc)
  (format *error-output* "  lext <input-file> [output-file]~%")
  (format *error-output* "~%~C[1mOPTIONS:~C[0m~%" #\Esc #\Esc)
  (format *error-output* "  ~C[32m<input-file>~C[0m   The template HTML/text file to render @@ forms.~%" #\Esc #\Esc)
  (format *error-output* "  ~C[32m[output-file]~C[0m  (Optional) File path to write the output. Defaults to stdout.~%~%" #\Esc #\Esc))

(defun main ()
  (let* ((args sb-ext:*posix-argv*)
         ;; The first element is the script/executable name, the rest are user args
         (user-args (cdr args))
         (input-file (first user-args))
         (output-file (second user-args)))
    (cond
      ((and input-file output-file)
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
           (sb-ext:exit :code 1))))
      (input-file
       (handler-case
           (let ((result (render-template input-file)))
             (write-string result)
             (finish-output)
             (sb-ext:exit :code 0))
         (error (e)
           (format *error-output* "~C[1;31m[Error]~C[0m Failed to render: ~A~%" #\Esc #\Esc e)
           (sb-ext:exit :code 1))))
      (t
       (print-help)
       (sb-ext:exit :code 1)))))

(main)
