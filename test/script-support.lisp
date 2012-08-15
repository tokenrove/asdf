(defpackage :asdf-test (:use :common-lisp))

(in-package #:asdf-test)

(declaim (optimize (speed 2) (safety 3) #-allegro (debug 3)))
(proclaim '(optimize (speed 2) (safety 3) #-allegro (debug 3)))

;;(format t "Evaluating asdf/test/script-support~%")

;; We can't use asdf:merge-pathnames* because ASDF isn't loaded yet.
;; We still want to work despite and host/device funkiness.
(defparameter *test-directory*
  (make-pathname :name nil :type nil :version nil
                 :defaults (or *load-truename* *compile-file-truename*)))
(defparameter *asdf-directory*
  (merge-pathnames
   (make-pathname :directory '(:relative :back) :defaults *test-directory*)
   *test-directory*))
(defparameter *asdf-lisp*
  (make-pathname :name "asdf" :type "lisp" :defaults *asdf-directory*))
(defparameter *asdf-fasl*
  (compile-file-pathname
   (let ((impl (string-downcase
                (or #+allegro
                    (ecase excl:*current-case-mode*
                      (:case-sensitive-lower :mlisp)
                      (:case-insensitive-upper :alisp))
                    #+armedbear :abcl
                    #+clisp :clisp
                    #+clozure :ccl
                    #+cmu :cmucl
                    #+corman :cormanlisp
                    #+digitool :mcl
                    #+ecl :ecl
                    #+gcl :gcl
                    #+lispworks :lispworks
		    #+mkcl :mkcl
                    #+sbcl :sbcl
                    #+scl :scl
                    #+xcl :xcl))))
     (merge-pathnames
      (make-pathname :directory `(:relative "tmp" "fasls" ,impl)
                     :defaults *asdf-directory*)
      *asdf-lisp*))))

(defun load-asdf ()
  (load *asdf-fasl*)
  (use-package :asdf :asdf-test)
  (setf *package* (find-package :asdf-test)))

(defun common-lisp-user::load-asdf ()
  (load-asdf))

#+allegro
(setf excl:*warn-on-nested-reader-conditionals* nil)

(defun native-namestring (x)
  (let ((p (pathname x)))
    #+clozure (ccl:native-translated-namestring p)
    #+(or cmu scl) (ext:unix-namestring p nil)
    #+sbcl (sb-ext:native-namestring p)
    #-(or clozure cmu sbcl scl) (namestring p)))

;;; code adapted from cl-launch http://www.cliki.net/cl-launch
(defun exit-lisp (return)
  #+allegro
  (excl:exit return)
  #+clisp
  (ext:quit return)
  #+(or cmu scl)
  (unix:unix-exit return)
  #+ecl
  (si:quit return)
  #+gcl
  (lisp:quit return)
  #+lispworks
  (lispworks:quit :status return :confirm nil :return nil :ignore-errors-p t)
  #+(or openmcl mcl)
  (ccl::quit return)
  #+mkcl
  (mk-ext:quit :exit-code return)
  #+sbcl #.(let ((exit (find-symbol "EXIT" :sb-ext))
                 (quit (find-symbol "QUIT" :sb-ext)))
             (cond
               (exit `(,exit :code return :abort t))
               (quit `(,quit :unix-status return :recklessly-p t))))
  #+(or abcl xcl)
  (ext:quit :status return)
  (error "Don't know how to quit Lisp; wanting to use exit code ~a" return))

(defun leave-lisp (message return)
  (fresh-line *error-output*)
  (when message
    (format *error-output* message)
    (terpri *error-output*))
  (finish-output *error-output*)
  (finish-output *standard-output*)
  (exit-lisp return))

(defmacro quit-on-error (&body body)
  `(call-quitting-on-error (lambda () ,@body)))

(defun call-quitting-on-error (thunk)
  "Unless the environment variable DEBUG_ASDF_TEST
is bound, write a message and exit on an error.  If
*asdf-test-debug* is true, enter the debugger."
  (handler-bind
      ((error (lambda (c)
                (format *error-output* "~&~a~&" c)
                (cond
                  ((ignore-errors (funcall (find-symbol "GETENV" :asdf) "DEBUG_ASDF_TEST"))
                   (break))
                  (t
                   (finish-output *standard-output*)
                   (finish-output *trace-output*)
                   (format *error-output* "~&ABORTING:~% ~S~%" c)
                   #+sbcl (sb-debug:backtrace 69)
                   #+clozure (ccl:print-call-history :count 69 :start-frame-number 1)
                   #+clisp (system::print-backtrace)
                   (format *error-output* "~&ABORTING:~% ~S~%" c)
                   (finish-output *error-output*)
                   (leave-lisp "~&Script failed~%" 1))))))
    (funcall thunk)
    (leave-lisp "~&Script succeeded~%" 0)))


;;; These are used by the upgrade tests

(defmacro quietly (&body body)
  `(call-quietly #'(lambda () ,@body)))

(defun call-quietly (thunk)
  (handler-bind (#+sbcl (sb-kernel:redefinition-warning #'muffle-warning))
    (funcall thunk)))

(defun load-asdf-lisp ()
  (load *asdf-lisp*))

(defun compile-asdf ()
  (ensure-directories-exist *asdf-fasl*)
  (compile-file *asdf-lisp* :output-file *asdf-fasl* :verbose t :print t))

(defun load-asdf-fasl ()
  (load *asdf-fasl*))

(defun compile-load-asdf ()
  ;; emulate the way asdf upgrades itself: load source, compile, load fasl.
  (load-asdf-lisp)
  (compile-asdf)
  (load-asdf-fasl))

(defun register-directory (dir)
  (pushnew dir (symbol-value (find-symbol (string :*central-registry*) :asdf))))

(defun asdf-load (x &key verbose)
  (let ((xoos (find-symbol (string :oos) :asdf))
        (xload-op (find-symbol (string :load-op) :asdf))
        (*load-print* verbose)
        (*load-verbose* verbose))
    (funcall xoos xload-op x :verbose verbose)))

(defun load-asdf-system (&rest keys)
  (quietly
   (register-directory *asdf-directory*)
   (apply 'asdf-load :asdf keys)))

(defun testing-asdf (thunk)
  (quit-on-error
   (quietly
    (funcall thunk)
    (register-directory *test-directory*)
    (asdf-load :test-module-depend))))

(defmacro test-asdf (&body body)
  `(testing-asdf #'(lambda () ,@body)))
