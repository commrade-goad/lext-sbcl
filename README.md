# LExt SBCL: High-Performance Template Engine & Script Runner in Common Lisp

`lext-sbcl` is a complete port of the original Scheme-based [lext](https://github.com/commrade-goad/lext) template preprocessor and script runner to **Steel Bank Common Lisp (SBCL)**. It replaces the original C-embedded Scheme s7 interpreter and `libffi` integration with native, compiled Common Lisp running on SBCL's highly optimized compiler and its premium native foreign function interface (`sb-alien`).

It maintains the same command-line ergonomics and features as the original [lext](https://github.com/commrade-goad/lext) but introduces:
1. **Unmatched Execution Speed:** Native compilation via SBCL's runtime instead of an interpreted s7 Scheme environment.
2. **Zero-Dependency Standalone Binary:** Compiles into a single optimized native executable (`lext`) that embeds its standard library (`basic.lisp`) as an internal string constant, making it completely self-contained.
3. **Robust Scripting Isolation:** The `-s` / `--script` runner spawns an isolated SBCL subprocess to execute script files, keeping your main process environment clean and robust.
4. **Rich FFI Ecosystem:** Direct mapping of C ABIs (structs, unions, enums, arrays, and callbacks) into Common Lisp using high-speed native CPU registers.

---

## Key Features

- **Embedded SBCL Engine:** A fully ANSI-compliant Common Lisp runtime optimized for template parsing and speed.
- **Dynamic FFI Layer:** Direct, native bindings via SBCL's `sb-alien` wrapper interface with support for passing structs/unions by value or pointer.
- **Scheme-style Ergonomics Wrapper:** Auto-imported macros and readers mapped directly in [basic.lisp](basic.lisp) (e.g., `#t`, `#f`, `define`, `fn`, `display`).
- **Standard Library Preloader:** Running with script mode auto-configures a clean execution context with the stdlib preloaded.
- **Flexible Argument Forwarding:** Pass command line arguments through to script runners seamlessly.
- **Low-Level Capture Engine:** Capture standard C stdout outputs (e.g., `printf`, `puts` from C binaries) directly into Lisp strings using tmpfs-backed redirect structures.

---

## Requirements & Building

### Dependencies
- **SBCL (Steel Bank Common Lisp)**: You need `sbcl` installed on your system.
  - On Gentoo: `emerge dev-lisp/sbcl`
  - On Debian/Ubuntu: `sudo apt install sbcl`
  - On Fedora: `sudo dnf install sbcl`
  - On Arch: `sudo pacman -S sbcl`

### Build the Standalone Binary
To compile the template engine and its embedded stdlib into a standalone optimized binary executable (`lext`), run:
```bash
sbcl --script build.lisp
```
This performs a high-optimization compilation of `basic.lisp` and `engine.lisp`, embeds `basic.lisp` inside the runtime image, and saves it as the optimized executable `./lext`.

---

## Usage Guide

### 1. Template Preprocessor Mode
In this mode, LExt reads an input file character-by-character, evaluates Lisp forms enclosed inside `@@(...)` using SBCL's reader, and writes the rendered results.
```bash
./lext <input-file> [output-file]
```
If `[output-file]` is omitted, the rendered output is written to standard output (`stdout`).

**Example template (`test.template`):**
```html
<!DOCTYPE html>
<html>
<body>
  <h1>@@(format nil "Hello ~A!" "User")</h1>
  <p>Two plus two is @@(+ 2 2)</p>
</body>
</html>
```

### 2. Lisp Script Runner Mode (`-s` / `--script`)
To run a raw Lisp script directly with the Scheme ergonomics and FFI wrapper preloaded:
```bash
./lext -s <script-file> [arguments...]
```
*Note: In script mode, all additional arguments after the script filename are automatically forwarded as command-line arguments to the script process.*

### 3. Other Flags
- **`-h` / `--help`**: Prints usage instructions.
- **`-v` / `--version`**: Prints the current version (`1.1.0-sbcl`).

---

## FFI & Compatibility API Reference

LExt's standard library is declared in [basic.lisp](basic.lisp). When executing scripts via the `-s` / `--script` flag, the following forms and macros are preloaded:

### Scheme Ergonomics
- **`#t` / `#f`**: Custom reader macros that evaluate to Common Lisp's `t` and `nil` respectively.
- **`(define name value)`**: Shorthand macro mapping directly to `defparameter`.
- **`(fn args &body body)`**: Shorthand macro mapping directly to `lambda`.
- **`(display msg)`**: Prints a message and instantly flushes standard output.

### FFI Library Management
- **`(ffi-open lib-path)`**: Registers and loads a shared library file (`.so`). Pass `nil` to target the main process space (allowing direct calls to standard C library routines like `puts` or `abs`).

### Type Declarations
- **`(define-c-struct name &rest fields)`**: Declares a native sequential C struct layout. Fields are defined as `(field-name field-type)`.
- **`(define-c-union name &rest fields)`**: Declares an overlapping memory union layout.
- **`(define-c-enum name &rest variants)`**: Declares a mapped enum of key-value integer variants.

**Supported Primitive FFI Types:**
- `void`
- `int` / `uint`
- `long` / `ulong`
- `char` / `uchar`
- `float`
- `double`
- `string` (converts between Common Lisp strings and C `char *` pointers)
- `pointer` or `(* void)` (generic `void *` pointer)
- `(* <type>)` (typed pointer, e.g., `(* uint32)`, `(* char)`)
- Sized integers: `int8`, `int16`, `int32`, `int64`, `uint8`, `uint16`, `uint32`, `uint64`

### Memory Operations
- **`(c-size type)`**: Returns the physical byte size of a declared FFI type layout.
- **`(@ ptr &rest path)`**: The unified reference and accessor operator. Direct replacement for verbose nested slot accessors. Supports `setf` mutation:
  ```lisp
  (setf (@ pkt :payload :i-val) 42)
  ```
- **`(addr alien-obj)`**: Retrieves the raw pointer address of an alien structure.
- **`(ptr+ sap-pointer byte-offset)`**: Performs raw address arithmetic on hardware pointers.
- **`(sap-to-alien sap type)`**: Casts a raw hardware pointer address back to a typed alien pointer.
- **`(c-cast ptr target-type)`**: Casts a typed pointer to another target FFI type.
- **`(null-ptr? ptr)`**: Returns `t` if the pointer points to address `0` (`NULL`).
- **`(c-memcpy dest src byte-count)`**: Blits memory blocks using native C `memcpy`.
- **`(c-memset dest byte-value byte-count)`**: Fills a memory block using native C `memset`.

### Memory Sandbox Allocations
- **`(with-heap-alloc (var type &optional count) &body body)`**: Allocates a typed block on the heap, ensuring it is automatically freed on block exit.
- **`(with-alloc (var type &optional (count 1)) &body body)`**: Allocates a typed block on the stack, cleaned up automatically on block exit.
- **`(with-c-array (var type lisp-list) &body body)`**: Converts a Common Lisp list of numbers into a contiguous C vector array.
- **`(with-c-string-array (var lisp-string-list) &body body)`**: Converts a list of Lisp strings into a null-terminated `char **` vector block.

### C Linkage & Callbacks
- **`(c-import name library c-name return-type arg-types &optional variadic-p)`**: Binds a foreign function signature directly to a Lisp function. If `variadic-p` is true, the macro will dynamically parse standard C format specifiers to infer argument registers.
- **`(define-c-callback name return-type arg-spec &body body)`**: Creates a callback function that native compiled C binaries can execute.
- **`(callback-ptr name)`**: Retrieves the foreign function pointer of a defined callback.

---

## Code Examples

### Example 1: Standard libc IO & Math
```lisp
(in-package :cl-user)

(define libc (ffi-open nil))

;; Import standard double cos(double)
(c-import c-cos libc "cos" double (double))
(format t "cos(0.0) = ~A~%" (c-cos 0.0)) ; Prints: cos(0.0) = 1.0d0

;; Import standard int puts(const char*)
(c-import c-puts libc "puts" int (string))
(c-puts "Hello from LExt FFI!")

;; Import variadic printf
(c-import c-printf libc "printf" int (string) t)
(c-printf "Welcome to ~A version ~A!~%" "LExt SBCL" "1.1.0")
```

### Example 2: Structs, Pointer Math, and Unions
```lisp
(in-package :cl-user)

(define-c-union variant-t
  (i-val int)
  (d-val double))

(define-c-struct packet-t
  (status int)
  (payload variant-t)
  (node-id uint64))

(with-heap-alloc (pkt packet-t)
  ;; Clear struct memory using custom memset
  (c-memset pkt 0 (c-size packet-t))

  ;; Populate structural fields
  (setf (@ pkt :status) 1)
  (setf (@ pkt :node-id) 123456)
  (setf (@ pkt :payload :i-val) 100)

  (format t "Status: ~A~%" (@ pkt :status))
  (format t "Node ID: ~A~%" (@ pkt :node-id))
  (format t "Payload Int: ~A~%" (@ pkt :payload :i-val))

  ;; Perform pointer math: step past status (4 bytes) and alignment (4 bytes) to payload (offset 8)
  (let* ((raw-sap (ptr+ pkt 8))
         (reconstructed (sap-to-alien raw-sap variant-t)))
    (format t "Reconstructed payload: ~A~%" (@ reconstructed :i-val))))
```

### Example 3: Spawning an SDL2 Window
You can test this by running `./lext -s sdl.lisp` which renders a black background in an 800x600 window:
```lisp
(in-package :cl-user)

(define sdl (ffi-open "libSDL2-2.0.so.0"))

(define SDL_INIT_VIDEO 32)
(define SDL_WINDOW_SHOWN 4)
(define SDL_RENDERER_ACCELERATED 2)

(c-import sdl-init sdl "SDL_Init" int (int))
(c-import sdl-create-window sdl "SDL_CreateWindow" pointer (string int int int int int))
(c-import sdl-create-renderer sdl "SDL_CreateRenderer" pointer (pointer int int))
(c-import sdl-set-render-draw-color sdl "SDL_SetRenderDrawColor" int (pointer int int int int))
(c-import sdl-render-clear sdl "SDL_RenderClear" int (pointer))
(c-import sdl-render-present sdl "SDL_RenderPresent" void (pointer))
(c-import sdl-delay sdl "SDL_Delay" void (int))
(c-import sdl-destroy-renderer sdl "SDL_DestroyRenderer" void (pointer))
(c-import sdl-destroy-window sdl "SDL_DestroyWindow" void (pointer))
(c-import sdl-quit sdl "SDL_Quit" void ())

(when (= (sdl-init SDL_INIT_VIDEO) 0)
  (let* ((win (sdl-create-window "LExt SBCL SDL2 Window" 100 100 800 600 SDL_WINDOW_SHOWN))
         (ren (sdl-create-renderer win -1 SDL_RENDERER_ACCELERATED)))
    (when (not (null-ptr? win))
      (sdl-set-render-draw-color ren 0 0 0 255)
      (sdl-render-clear ren)
      (sdl-render-present ren)
      (sdl-delay 3000) ; display for 3 seconds
      (sdl-destroy-renderer ren)
      (sdl-destroy-window win)))
  (sdl-quit))
```

---

## License
`lext-sbcl` is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for details.
