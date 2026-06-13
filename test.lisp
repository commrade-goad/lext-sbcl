;;;; test-matrix.lisp - Validation Suite for Matrix Engine Stdlib
(in-package :cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (handler-bind ((warning #'muffle-warning))
    (load (compile-file "basic.lisp"))))

(format t "~%==================================================~%")
(format t "RUNNING CORE FFI & DEVSTDLIB MATRIX VERIFICATION~%")
(format t "==================================================~%~%")

;; =========================================================================
;; 1. Layouts, Sizing, and Reference Operator (@) Validation
;; =========================================================================
(format t "[TEST] Section 4 & 5: Structs, Unions, Enums, & Accessors... ")

(define-c-enum status-t :idle :running (:error -1))

(define-c-union variant-t
  (i-val int)
  (d-val double))

(define-c-struct packet-t
  (status status-t)
  (payload variant-t)
  (node-id uint64))

(define-c-struct pointer-test-t
  (void-ptr (* void))
  (uint32-ptr (* uint32)))

;; Validate sizing checks
(assert (> (c-size packet-t) 0))
(assert (> (c-size pointer-test-t) 0))

(with-heap-alloc (pkt packet-t)
  ;; Clear foreign block space completely via custom memset
  (c-memset pkt 0 (c-size packet-t))

  ;; Mutate data depths via nested reference routing matrix
  (setf (@ pkt :node-id) 144000)
  (setf (@ pkt :status) :running)
  (setf (@ pkt :payload :i-val) 42)

  ;; Extract and assert deep structure targets
  (assert (= (@ pkt :node-id) 144000))
  (assert (eq (@ pkt :status) :running))
  (assert (= (@ pkt :payload :i-val) 42))

  ;; Validate reference operator fall-through behavior (untyped direct deref)
  (assert (not (null-ptr? pkt)))
  (assert (null-ptr? (null-ptr)))

  ;; Validate temporary C string stack allocation and casting back
  (with-c-string (s "TestString")
    (assert (string= (c-string-from-ptr s) "TestString")))

  ;; Validate hardware-pointer math and reconstruction back to layout pointers
  (let* ((raw-sap (ptr+ pkt 8)) ;; step past status and alignment padding
         (reconstructed-union (sap-to-alien raw-sap variant-t)))
    (assert (= (@ reconstructed-union :i-val) 42))))
(format t "PASSED~%")


;; =========================================================================
;; 2. Sandbox Array Framework & Byte Blitting Validation
;; =========================================================================
(format t "[TEST] Section 5 & 6: Hardware Arrays & Memory Blitting... ")

;; Stack allocation trace & memcpy validation
(with-alloc (src int 4)
  (setf (@ src 0) 100)
  (setf (@ src 1) 200)
  (with-alloc (dst int 2)
    (c-memcpy (addr dst) (addr src) (* 2 (c-size int)))
    (assert (= (@ dst 0) 100))
    (assert (= (@ dst 1) 200))))

;; List array transformation validation
(with-c-array (numbers double '(12.34d0 56.78d0))
  (assert (= (@ numbers 0) 12.34d0))
  (assert (= (@ numbers 1) 56.78d0)))

;; String array mapping (char** vector) layout validation
(with-c-string-array (argv '("tmenu" "--launcher" "sway"))
  (assert (string= (@ argv 0) "tmenu"))
  (assert (string= (@ argv 1) "--launcher"))
  (assert (string= (@ argv 2) "sway"))
  (assert (null (@ argv 3))))
(format t "PASSED~%")


;; =========================================================================
;; 3. Routine Importer & Native C Callback Validation
;; =========================================================================
(format t "[TEST] Section 7: Importer and Callbacks... ")

;; Static routine linkage (using standard libc abs layout pre-linked in core image)
(c-import c-abs nil "abs" int (int))
(assert (= (c-abs -777) 777))

;; Variadic interface dynamic expansion generation
(c-import c-sprintf nil "sprintf" int (pointer string) t)

;; Define callback interface target block
(define-c-callback sample-dispatcher int ((a int) (b int))
  (+ a b))

;; Validate lookup point vector allocation
(assert (not (sb-sys:sap= (sb-alien:alien-sap (callback-ptr sample-dispatcher)) (sb-sys:int-sap 0))))
(format t "PASSED~%")


;; =========================================================================
;; 4. Universal Capturing Engine Validation
;; =========================================================================
(format t "[TEST] Section 2: Low-Level POSIX Redirection... ")

(let ((intercepted-output
        (capture
          (display "Lisp layer writing to standard stdout buffer.")
          ;; Fire a native variadic C print instruction straight through to stdout
          (with-alloc (buf char 128)
            (c-sprintf (addr buf) "C-Engine Variadic Value: %d" 9000)
            (c-import c-puts nil "puts" int (pointer))
            (c-puts (addr buf))))))

  (assert (search "Lisp layer writing" intercepted-output))
  (assert (search "C-Engine Variadic Value: 9000" intercepted-output)))
(format t "PASSED~%")


;; =========================================================================
;; 5. LExt Raw String Escape Validation
;; =========================================================================
(format t "[TEST] Section 8: LExt Raw String Escape... ")
(handler-bind ((warning #'muffle-warning))
  (pushnew :lext-build *features*)
  (load (compile-file "lext.lisp")))

(let ((res (with-input-from-string (s "r\"stuff\\here\"")
             (handle-lisp-tag s))))
  (assert (string= res "stuff\\here")))

(let ((res (with-input-from-string (s "R\"C:\\Windows\\System32\"")
             (handle-lisp-tag s))))
  (assert (string= res "C:\\Windows\\System32")))

(let ((res (with-input-from-string (s "(let ((results '(1 2 3))) (first results))")
             (handle-lisp-tag s))))
  (assert (string= res "1")))

(format t "PASSED~%")

(format t "~%==================================================~%")
(format t "SUCCESS: ALL CORE ENGINE MATRIX SYSTEMS OPERATIONAL~%")
(format t "==================================================~%")
(sb-ext:exit :code 0)
