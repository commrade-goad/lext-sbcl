;;;; basic.lisp - The Ultimate Maxed-Out FFI & Dev Stdlib for SBCL Matrix Engine
(in-package :cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (shadow 'addr))

;; =========================================================================
;; 1. Scheme-ish Compatibility & Ergonomics Layer
;; =========================================================================

;; Map #f and #t to NIL and T in the Lisp reader for hybrid logic syntax
(set-dispatch-macro-character #\# #\f (lambda (s c sub) (declare (ignore s c sub)) nil))
(set-dispatch-macro-character #\# #\t (lambda (s c sub) (declare (ignore s c sub)) t))

;; Clean declarative syntax aliases
(defmacro define (name value)
  "Convenient top-level parameter definitions mapping closer to Scheme."
  `(defparameter ,name ,value))

(defmacro fn (args &body body)
  "Shorthand lambda instantiation expression syntax."
  `(lambda ,args ,@body))

(defun display (msg)
  "Expressive print helper that instantly flushes to stdout.
   Ideal for live template tracing without waiting for system buffers."
  (format t "~A~%" msg)
  (finish-output))


;; =========================================================================
;; 2. Low-Level POSIX Redirection Engine (Universal Capturing)
;; =========================================================================

(sb-alien:define-alien-routine "fflush" sb-alien:int (stream (* t)))
(sb-alien:define-alien-routine "dup" sb-alien:int (oldfd sb-alien:int))
(sb-alien:define-alien-routine "dup2" sb-alien:int (oldfd sb-alien:int) (newfd sb-alien:int))
(sb-alien:define-alien-routine ("close" c-close) sb-alien:int (fd sb-alien:int))
(sb-alien:define-alien-routine "tmpfile" (* t))
(sb-alien:define-alien-routine "fileno" sb-alien:int (stream (* t)))
(sb-alien:define-alien-routine "rewind" sb-alien:void (stream (* t)))
(sb-alien:define-alien-routine "fclose" sb-alien:int (stream (* t)))
(sb-alien:define-alien-routine "fgetc" sb-alien:int (stream (* t)))

(defmacro capture (&body body)
  "Evaluates any code block while intercepting all C/POSIX stdout writes,
   returning them cleanly as a native Lisp string. Uses an auto-deleting
   tmpfs-backed file stream to handle infinite output sizes without blocking."
  (let ((g-saved (gensym "SAVED"))
        (g-tmp (gensym "TMP"))
        (g-fd (gensym "FD"))
        (g-str (gensym "STR"))
        (g-char (gensym "CHAR"))
        (null-ptr `(sb-alien:sap-alien (sb-sys:int-sap 0) (* t))))
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
           (c-close ,g-saved))                    ; Release tracking pointer descriptor
         (rewind ,g-tmp)                        ; Seek to beginning of captured byte data
         (let ((,g-str (with-output-to-string (s)
                         (loop for ,g-char = (fgetc ,g-tmp)
                               until (= ,g-char -1)
                               do (write-char (code-char ,g-char) s)))))
           (fclose ,g-tmp)                      ; Closes stream and auto-purges underlying disk file
           ,g-str)))))                          ; Ship native string output back to caller

(sb-alien:define-alien-routine "memcpy" (* t)
  (dest (* t)) (src (* t)) (n sb-alien:unsigned-long))

(sb-alien:define-alien-routine "memset" (* t)
  (s (* t)) (c sb-alien:int) (n sb-alien:unsigned-long))

;; =========================================================================
;; 3. Rich Broad-Spectrum Type Translation Matrix
;; =========================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun translate-ffi-type (type)
    "Maps clean shorthand symbols and explicit bit-width specifiers to native
     compiler primitive descriptors."
    (cond
      ((and (listp type) (eq (car type) '*))
       (let ((inner (second type)))
         (if (eq inner 'void)
             '(* t)
             `(* ,(translate-ffi-type inner)))))
      (t
       (case type
         ;; Standard Unspecified Primitives
         (void        'sb-alien:void)
         (int         'sb-alien:int)
         (uint        'sb-alien:unsigned-int)
         (long        'sb-alien:long)
         (ulong       'sb-alien:unsigned-long)
         (size_t      'sb-alien:unsigned-long)
         (char        'sb-alien:char)
         (uchar       'sb-alien:unsigned-char)
         (float       'sb-alien:single-float)
         (double      'sb-alien:double-float)
         (string      'sb-alien:c-string)
         (pointer     '(* t))

         ;; Explicit Sized Fixed-Width Integer Types
         (int8        '(sb-alien:signed 8))
         (int16       '(sb-alien:signed 16))
         (int32       '(sb-alien:signed 32))
         (int64       '(sb-alien:signed 64))
         (uint8       '(sb-alien:unsigned 8))
         (uint16      '(sb-alien:unsigned 16))
         (uint32      '(sb-alien:unsigned 32))
         (uint64      '(sb-alien:unsigned 64))
         (t type))))))


;; =========================================================================
;; 4. Comprehensive Layout Declarators (Structs, Unions, Enums)
;; =========================================================================

(defmacro define-c-struct (name &rest fields)
  "Declare a native standard sequential C struct layout.
   Example: (define-c-struct account-node (id int) (balance double))"
  `(sb-alien:define-alien-type ,name
     (sb-alien:struct nil
       ,@(loop for (f-name f-type) in fields
               collect (list (intern (symbol-name f-name) "KEYWORD") (translate-ffi-type f-type))))))

(defmacro define-c-union (name &rest fields)
  "Declare an overlapping memory C union layout. Crucial for handling raw network
   buffers, dynamic variant values, or processing window subsystem events packets (like X11)."
  `(sb-alien:define-alien-type ,name
     (sb-alien:union nil
       ,@(loop for (f-name f-type) in fields
               collect (list (intern (symbol-name f-name) "KEYWORD") (translate-ffi-type f-type))))))

(defmacro define-c-enum (name &rest variants)
  "Maps sequential key-value integer lists. Useful for managing operational states.
   Example: (define-c-enum status-t :pending :active (:error -1))"
  `(sb-alien:define-alien-type ,name (sb-alien:enum nil ,@variants)))


;; =========================================================================
;; 5. The Ultimate Unified Reference Operator (@) & Memory Math
;; =========================================================================

(defmacro c-size (type)
  "Returns the absolute physical size of a designated FFI type layout in bytes.
   Essential for manual buffer sizing and pointer stepping math."
  `(sb-alien:alien-size ,(translate-ffi-type type) :bytes))

(defmacro with-heap-alloc ((var type &optional count) &body body)
  "Allocates directly on the persistent system heap instead of the stack.
   If count is provided, allocates an array of that size.
   Guarantees absolute unwind block safety and automated memory liberation on exit."
  (let ((a-type (translate-ffi-type type)))
    `(let ((,var (sb-alien:make-alien ,(if count `(sb-alien:array ,a-type ,count) a-type))))
       (unwind-protect
            (progn ,@body)
         (sb-alien:free-alien ,var)))))

(defmacro @ (ptr &rest path)
  "The ultimate pointer navigator. Replaces long alien accessor chains seamlessly.
   - If no path: Dereferences a raw pointer data node.
   - If a number: Indexes into a native contiguous array block.
   - If a keyword/symbol: Extracts a specific structural or union field member slot.

   Fully supports nested routing and SETF value mutations!
   Example: (@ event :xany :window) or (setf (@ item :cost) 15000)"
  (let ((result ptr))
    (dolist (step path)
      (setf result
            (cond
              ((or (keywordp step) (symbolp step))
               `(sb-alien:slot ,result ',step))
              ((numberp step)
               `(sb-alien:deref ,result ,step))
              (t `(sb-alien:deref ,result ,step)))))
    (if (equal result ptr)
        `(sb-alien:deref ,ptr)
        result)))

(defun null-ptr? (ptr)
  "Returns true if the foreign pointer address targets absolute structural zero."
  (sb-sys:sap= (sb-alien:alien-sap ptr) (sb-sys:int-sap 0)))

(defmacro ptr+ (sap-pointer byte-offset)
  "Executes lightning-fast manual address math skips over pointer chains or
   iterating through raw byte arrays."
  `(sb-sys:sap+ (sb-alien:alien-sap ,sap-pointer) ,byte-offset))

(defmacro sap-to-alien (sap type)
  "Reconstructs a raw SB-SYS hardware pointer (SAP) back into a fully typed FFI object pointer.
   Perfect companion for finishing manual math layouts using (ptr+ ...)"
  `(sb-alien:sap-alien ,sap (* ,(translate-ffi-type type))))

(defmacro c-cast (ptr target-type)
  "Typecasts an existing alien pointer to another designated structural FFI layout definition."
  `(sb-alien:cast ,ptr ,(translate-ffi-type target-type)))

(defmacro addr (alien-obj)
  "Retrieves the raw physical memory address pointer pointing to the current alien structural entity."
  `(sb-alien:addr ,alien-obj))

;; Place this at the bottom of SECTION 5:
(defmacro c-memcpy (dest src byte-count)
  "Blit raw memory blocks around at lightning speed using native C memcpy."
  `(memcpy ,dest ,src ,byte-count))

(defmacro c-memset (dest byte-value byte-count)
  "Fill a foreign memory block with a fixed byte value (e.g., zeroing out a struct)."
  `(memset ,dest ,byte-value ,byte-count))

;; =========================================================================
;; 6. Memory Sandbox Isolation Arrays
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
        (g-alloc (gensym "ALLOC"))
        (a-type (translate-ffi-type type)))
    `(let* ((,g-list ,lisp-list)
            (,g-len (length ,g-list)))
       (let* ((,g-alloc (sb-alien:make-alien (sb-alien:array ,a-type 1) ,g-len))
              (,var (sb-alien:addr (sb-alien:deref (sb-alien:deref ,g-alloc) 0))))
         (unwind-protect
              (progn
                (loop for ,g-idx from 0 for item in ,g-list
                      do (setf (sb-alien:deref ,var ,g-idx) item))
                ,@body)
            (sb-alien:free-alien ,g-alloc))))))

(defmacro with-c-string-array ((var lisp-string-list) &body body)
  "Converts a list of Lisp strings into a native null-terminated (char** ) block vector.
   Crucial for calling custom CLI tools, parsing arguments, or feeding layouts to C kernels."
  (let ((g-list (gensym "LIST"))
        (g-len (gensym "LEN"))
        (g-idx (gensym "IDX"))
        (g-alloc (gensym "ALLOC")))
    `(let* ((,g-list ,lisp-string-list)
            (,g-len (length ,g-list)))
       (let* ((,g-alloc (sb-alien:make-alien (sb-alien:array sb-alien:c-string 1) (1+ ,g-len)))
              (,var (sb-alien:addr (sb-alien:deref (sb-alien:deref ,g-alloc) 0))))
         (unwind-protect
              (progn
                (loop for ,g-idx from 0 for str in ,g-list
                      do (setf (sb-alien:deref ,var ,g-idx) str))
                (setf (sb-alien:deref ,var ,g-len) nil)
                ,@body)
            (sb-alien:free-alien ,g-alloc))))))


;; =========================================================================
;; 7. Flexible Variadic Routine Importer Engine
;; =========================================================================

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun parse-printf-specifiers (fmt-str)
    "Parses layout strings to extract and align expected C-types on the CPU execution register."
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
      (nreverse types))))

(defun ffi-open (lib-path)
  "Safely registers shared object libraries to the active process workspace runtime."
  (when (and lib-path (stringp lib-path))
    (sb-alien:load-shared-object lib-path))
  lib-path)

(defmacro c-import (name library c-name return-type arg-types &optional variadic-p)
  "Binds foreign native procedures directly into Lisp space.
   Handles static-typed signatures as uniform functional pointers and auto-resolves
   variadic parameters dynamically on invocation."
  (declare (ignore library))
  (let ((real-return (translate-ffi-type return-type))
        (real-fixed-args (mapcar #'translate-ffi-type arg-types)))
    (if (not variadic-p)
        `(sb-alien:define-alien-routine (,c-name ,name) ,real-return
           ,@(loop for type in real-fixed-args for idx from 1
                  collect (list (intern (format nil "ARG~A" idx)) type)))
        `(defmacro ,name (&rest args)
           (let* ((num-fixed ,(length arg-types))
                  (var-args (subseq args num-fixed))
                  (fmt-arg (nth (1- num-fixed) args))
                  (inferred-types (if (stringp fmt-arg)
                                      (parse-printf-specifiers fmt-arg)
                                      (mapcar (lambda (a) (declare (ignore a)) 'sb-alien:int) var-args)))
                  (all-arg-types (append ',real-fixed-args inferred-types)))
             `(sb-alien:alien-funcall
               (sb-alien:extern-alien ,,c-name (sb-alien:function ,',real-return ,@all-arg-types))
               ,@args))))))


(defmacro define-c-callback (name return-type arg-spec &body body)
  "Defines an entry point function that raw C binaries can execute natively.
   Automatically integrates into your custom FFI type translation matrix."
  `(sb-alien:define-alien-callable ,name
       ,(translate-ffi-type return-type)
       ,(loop for (a-name a-type) in arg-spec
              collect (list a-name (translate-ffi-type a-type)))
     ,@body))

(defmacro callback-ptr (name)
  "Retrieves the raw foreign function pointer of a defined callback to pass into C layers."
  `(sb-alien:alien-callable-function ',name))
