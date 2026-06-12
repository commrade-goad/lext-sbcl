;;;; sdl.lisp - SDL2 Window & Renderer demo for SBCL Matrix Engine
(in-package :cl-user)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (load "basic.lisp"))

;; Load SDL2 shared library
(ffi-open "libSDL2-2.0.so")

;; Import SDL2 APIs
(c-import sdl-init nil                  "SDL_Init" int (uint32))
(c-import sdl-create-window nil         "SDL_CreateWindow" pointer (string int int int int uint32))
(c-import sdl-create-renderer nil       "SDL_CreateRenderer" pointer (pointer int uint32))
(c-import sdl-set-render-draw-color nil "SDL_SetRenderDrawColor" int (pointer uint8 uint8 uint8 uint8))
(c-import sdl-render-clear nil          "SDL_RenderClear" int (pointer))
(c-import sdl-render-present nil        "SDL_RenderPresent" void (pointer))
(c-import sdl-poll-event nil            "SDL_PollEvent" int (pointer))
(c-import sdl-delay nil                 "SDL_Delay" void (uint32))
(c-import sdl-destroy-renderer nil      "SDL_DestroyRenderer" void (pointer))
(c-import sdl-destroy-window nil        "SDL_DestroyWindow" void (pointer))
(c-import sdl-quit-ffi nil              "SDL_Quit" void ())

(defun main ()
  (format t "Initializing SDL2...~%")
  (if (< (sdl-init #x00000020) 0) ; SDL_INIT_VIDEO
      (error "Failed to initialize SDL2")
      (format t "SDL2 Initialized.~%"))
  
  (format t "Creating Window...~%")
  (let ((window (sdl-create-window "SDL2 800x600 Black Background"
                                   #x2FFF0000 ; SDL_WINDOWPOS_CENTERED
                                   #x2FFF0000 ; SDL_WINDOWPOS_CENTERED
                                   800
                                   600
                                   #x00000004))) ; SDL_WINDOW_SHOWN
    (if (null-ptr? window)
        (progn
          (sdl-quit-ffi)
          (error "Failed to create window"))
        (format t "Window Created.~%"))

    (format t "Creating Renderer...~%")
    (let ((renderer (sdl-create-renderer window -1 #x00000002))) ; SDL_RENDERER_ACCELERATED
      (if (null-ptr? renderer)
          (progn
            (sdl-destroy-window window)
            (sdl-quit-ffi)
            (error "Failed to create renderer"))
          (format t "Renderer Created.~%"))

      (format t "Starting Main Loop...~%")
      (unwind-protect
           (with-alloc (event uint32 14) ; 56 bytes = 14 * 4 bytes
             (let ((running t))
               (loop while running
                     do (progn
                          ;; Process events
                          (loop while (> (sdl-poll-event (addr event)) 0)
                                do (let ((event-type (@ event 0)))
                                     (format t "Polled event: ~X~%" event-type)
                                     (when (= event-type #x100) ; SDL_QUIT
                                       (setf running nil))))
                          
                          ;; Render black background
                          (sdl-set-render-draw-color renderer 0 0 0 255)
                          (sdl-render-clear renderer)
                          (sdl-render-present renderer)
                          
                          ;; Delay to avoid hogging CPU
                          (sdl-delay 16)))))
        ;; Cleanup
        (format t "Cleaning up...~%")
        (sdl-destroy-renderer renderer)
        (sdl-destroy-window window)
        (sdl-quit-ffi)
        (format t "SDL2 Shutdown Complete.~%")))))

(main)
