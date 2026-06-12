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
                 (member (car lisp-form) '(defun defparameter defvar setf defmacro progn)))
            ""
            (if (null evaluation-result) "" (princ-to-string evaluation-result))))
    (error (e)
      (format nil "[Template Error: ~A]" e))))

(defun render-template (filename)
  "Reads a template file character-by-character and delegates code blocks to the reader."
  (with-output-to-string (output-buffer)
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
                          (when (and next-c (char= next-c #\Newline))
                            (read-char file-stream)))
                        (write-string rendered-tag output-buffer))))

                 ;; Route normal HTML characters straight to our output buffer
                 (t (write-char char output-buffer)))))))

;; --- Testing Execution ---

(defvar template-file "sample_template.html")

(format t "--- Processing Template File: ~A ---~%" template-file)
(let ((result (render-template template-file)))
  (format t "~A~%" result))
