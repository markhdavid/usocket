;;;; -*- Mode: Lisp -*-
;;;; $Id$
;;;; $URL$

;;;; See the LICENSE file for licensing information.

(defsystem usocket
    :name "usocket"
    :author "Erik Enge & Erik Huelsmann"
    :maintainer "Chun Tian (binghe) & Hans Huebner"
    :version "0.6.2"
    :licence "MIT"
    :description "Universal socket library for Common Lisp"
    :depends-on (#+(or sbcl ecl) :sb-bsd-sockets)
    :components ((:file "package")
		 (:module "vendor" :depends-on ("package")
		  :components ((:file "split-sequence")
			       #+mcl (:file "kqueue")
			       #+mcl (:file "OpenTransportUDP")
			       (:file "spawn-thread")))
		 (:file "usocket" :depends-on ("vendor"))
		 (:file "condition" :depends-on ("usocket"))
		 (:module "backend" :depends-on ("condition")
		  :components (#+abcl		(:file "abcl")
			       #+clisp		(:file "clisp")
			       #+cmu		(:file "cmucl")
			       #+scl		(:file "scl")
			       #+ecl		(:file "ecl")
			       #+(or sbcl ecl)	(:file "sbcl"
						 :depends-on (#+ecl "ecl"))
			       #+lispworks	(:file "lispworks")
			       #+mcl		(:file "mcl")
			       #+mocl		(:file "mocl")
			       #+openmcl	(:file "openmcl")
			       #+allegro	(:file "allegro")))
		 (:file "option" :depends-on ("backend"))
		 (:file "server" :depends-on ("backend" "option"))))

(defmethod perform ((op test-op) (c (eql (find-system :usocket))))
  (oos 'load-op :usocket-test)
  (oos 'test-op :usocket-test))
