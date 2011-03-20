;;;; $Id$
;;;; $URL$

;;;; See LICENSE for licensing information.

(in-package :usocket)

;; There's no way to preload the sockets library other than by requiring it
;;
;; ECL sockets has been forked off sb-bsd-sockets and implements the
;; same interface. We use the same file for now.
#+ecl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sockets))

#+sbcl
(progn
  #-win32
  (defun get-host-name ()
    (sb-unix:unix-gethostname))

  ;; we assume winsock has already been loaded, after all,
  ;; we already loaded sb-bsd-sockets and sb-alien
  #+win32
  (defun get-host-name ()
    (sb-alien:with-alien ((buf (sb-alien:array sb-alien:char 256)))
       (let ((result (sb-alien:alien-funcall
                      (sb-alien:extern-alien "gethostname"
                                             (sb-alien:function sb-alien:int
                                                                (* sb-alien:char)
                                                                sb-alien:int))
                      (sb-alien:cast buf (* sb-alien:char))
                      256)))
         (when (= result 0)
           (sb-alien:cast buf sb-alien:c-string))))))

#+ecl
(progn
  #-:wsock
  (ffi:clines
   "#include <errno.h>"
   "#include <sys/socket.h>")
  #+:wsock
  (ffi:clines
   "#ifndef FD_SETSIZE"
   "#define FD_SETSIZE 1024"
   "#endif"
   "#include <winsock2.h>")

  (ffi:clines
   #+:msvc "#include <time.h>"
   #-:msvc "#include <sys/time.h>"
   "#include <ecl/ecl-inl.h>")

  #+:prefixed-api
  (ffi:clines
   "#define CONS(x, y) ecl_cons((x), (y))"
   "#define MAKE_INTEGER(x) ecl_make_integer((x))")
  #-:prefixed-api
  (ffi:clines
   "#define CONS(x, y) make_cons((x), (y))"
   "#define MAKE_INTEGER(x) make_integer((x))")

  (defun fd-setsize ()
    (ffi:c-inline () () :fixnum
     "FD_SETSIZE" :one-liner t))

  (defun fdset-alloc ()
    (ffi:c-inline () () :pointer-void
     "ecl_alloc_atomic(sizeof(fd_set))" :one-liner t))

  (defun fdset-zero (fdset)
    (ffi:c-inline (fdset) (:pointer-void) :void
     "FD_ZERO((fd_set*)#0)" :one-liner t))

  (defun fdset-set (fdset fd)
    (ffi:c-inline (fdset fd) (:pointer-void :fixnum) :void
     "FD_SET(#1,(fd_set*)#0)" :one-liner t))

  (defun fdset-clr (fdset fd)
    (ffi:c-inline (fdset fd) (:pointer-void :fixnum) :void
     "FD_CLR(#1,(fd_set*)#0)" :one-liner t))

  (defun fdset-fd-isset (fdset fd)
    (ffi:c-inline (fdset fd) (:pointer-void :fixnum) :bool
     "FD_ISSET(#1,(fd_set*)#0)" :one-liner t))

  (declaim (inline fd-setsize
                   fdset-alloc
                   fdset-zero
                   fdset-set
                   fdset-clr
                   fdset-fd-isset))

  (defun get-host-name ()
    (ffi:c-inline
     () () :object
     "{ char *buf = ecl_alloc_atomic(257);

        if (gethostname(buf,256) == 0)
          @(return) = make_simple_base_string(buf);
        else
          @(return) = Cnil;
      }" :one-liner nil :side-effects nil))

  (defun read-select (wl to-secs &optional (to-musecs 0))
    (let* ((sockets (wait-list-waiters wl))
           (rfds (wait-list-%wait wl))
           (max-fd (reduce #'(lambda (x y)
                               (let ((sy (sb-bsd-sockets:socket-file-descriptor
                                          (socket y))))
                                 (if (< x sy) sy x)))
                           (cdr sockets)
                           :initial-value (sb-bsd-sockets:socket-file-descriptor
                                           (socket (car sockets))))))
      (fdset-zero rfds)
      (dolist (sock sockets)
        (fdset-set rfds (sb-bsd-sockets:socket-file-descriptor
                         (socket sock))))
      (let ((count
             (ffi:c-inline (to-secs to-musecs rfds max-fd)
                           (t :unsigned-int :pointer-void :int)
                           :int
      "
          int count;
          struct timeval tv;

          if (#0 != Cnil) {
            tv.tv_sec = fixnnint(#0);
            tv.tv_usec = #1;
          }
        @(return) = select(#3 + 1, (fd_set*)#2, NULL, NULL,
                           (#0 != Cnil) ? &tv : NULL);
" :one-liner nil)))
        (cond
          ((= 0 count)
           (values nil nil))
          ((< count 0)
           ;; check for EINTR and EAGAIN; these should not err
           (values nil (ffi:c-inline () () :int "errno" :one-liner t)))
          (t
           (dolist (sock sockets)
             (when (fdset-fd-isset rfds (sb-bsd-sockets:socket-file-descriptor
                                         (socket sock)))
               (setf (state sock) :READ))))))))
) ; progn

(defun map-socket-error (sock-err)
  (map-errno-error (sb-bsd-sockets::socket-error-errno sock-err)))

(defparameter +sbcl-condition-map+
  '((interrupted-error . interrupted-condition)))

(defparameter +sbcl-error-map+
  `((sb-bsd-sockets:address-in-use-error . address-in-use-error)
    (sb-bsd-sockets::no-address-error . address-not-available-error)
    (sb-bsd-sockets:bad-file-descriptor-error . bad-file-descriptor-error)
    (sb-bsd-sockets:connection-refused-error . connection-refused-error)
    (sb-bsd-sockets:invalid-argument-error . invalid-argument-error)
    (sb-bsd-sockets:no-buffers-error . no-buffers-error)
    (sb-bsd-sockets:operation-not-supported-error
     . operation-not-supported-error)
    (sb-bsd-sockets:operation-not-permitted-error
     . operation-not-permitted-error)
    (sb-bsd-sockets:protocol-not-supported-error
     . protocol-not-supported-error)
    #-ecl
    (sb-bsd-sockets:unknown-protocol
     . protocol-not-supported-error)
    (sb-bsd-sockets:socket-type-not-supported-error
     . socket-type-not-supported-error)
    (sb-bsd-sockets:network-unreachable-error . network-unreachable-error)
    (sb-bsd-sockets:operation-timeout-error . timeout-error)
    #-ecl
    (sb-sys:io-timeout . timeout-error)
    (sb-bsd-sockets:socket-error . ,#'map-socket-error)

    ;; Nameservice errors: mapped to unknown-error
    #-ecl #-ecl #-ecl
    (sb-bsd-sockets:no-recovery-error . ns-no-recovery-error)
    (sb-bsd-sockets:try-again-error . ns-try-again-condition)
    (sb-bsd-sockets:host-not-found-error . ns-host-not-found-error)))

(defun handle-condition (condition &optional (socket nil))
  "Dispatch correct usocket condition."
  (typecase condition
    (serious-condition (let* ((usock-error (cdr (assoc (type-of condition)
                                           +sbcl-error-map+)))
                  (usock-error (if (functionp usock-error)
                                   (funcall usock-error condition)
                                 usock-error)))
             (when usock-error
                 (error usock-error :socket socket))))
    (condition (let* ((usock-cond (cdr (assoc (type-of condition)
                                              +sbcl-condition-map+)))
                      (usock-cond (if (functionp usock-cond)
                                      (funcall usock-cond condition)
                                    usock-cond)))
                 (if usock-cond
                     (signal usock-cond :socket socket))))))

(defvar *dummy-stream*
  (let ((stream (make-broadcast-stream)))
    (close stream)
    stream))

(defun socket-connect (host port &key (protocol :stream) (element-type 'character)
                       timeout deadline (nodelay t nodelay-specified)
                       local-host local-port
		       &aux
		       (sockopt-tcp-nodelay-p
			(fboundp 'sb-bsd-sockets::sockopt-tcp-nodelay)))
  (when deadline (unsupported 'deadline 'socket-connect))
  #+ecl
  (when timeout (unsupported 'timeout 'socket-connect))
  (when (and nodelay-specified
             ;; 20080802: ECL added this function to its sockets
             ;; package today. There's no guarantee the functions
             ;; we need are available, but we can make sure not to
             ;; call them if they aren't
             (not sockopt-tcp-nodelay-p))
    (unsupported 'nodelay 'socket-connect))

  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                               :type protocol
                               :protocol (case protocol
                                           (:stream :tcp)
                                           (:datagram :udp))))
        (local-host (host-to-vector-quad (or local-host *wildcard-host*)))
        (local-port (or local-port *auto-port*))
        usocket ok)
    (unwind-protect
         (progn
           (ecase protocol
             (:stream
              ;; If make a real socket stream before the socket is
              ;; connected, it gets a misleading name so supply a
              ;; dummy value to start with.
              (setf usocket (make-stream-socket :socket socket :stream *dummy-stream*))
              ;; binghe: use SOCKOPT-TCP-NODELAY as internal symbol
              ;;         to pass compilation on ECL without it.
              (when (and nodelay-specified sockopt-tcp-nodelay-p)
                (setf (sb-bsd-sockets::sockopt-tcp-nodelay socket) nodelay))
              (when (or local-host local-port)
                (sb-bsd-sockets:socket-bind socket local-host local-port))
              (with-mapped-conditions (usocket)
                (sb-bsd-sockets:socket-connect socket (host-to-vector-quad host) port)
                ;; Now that we're connected make the stream.
                (setf (socket-stream usocket)
                      (sb-bsd-sockets:socket-make-stream socket
                                                         :input t
                                                         :output t
                                                         :buffering :full
                                                         #+sbcl #+sbcl
                                                         :timeout timeout
                                                         :element-type element-type))))
             (:datagram
              (when (or local-host local-port)
                (sb-bsd-sockets:socket-bind socket
                                            (host-to-vector-quad
                                             (or local-host *wildcard-host*))
                                            (or local-port *auto-port*)))
              (setf usocket (make-datagram-socket socket))
              (when (and host port)
                (with-mapped-conditions (usocket)
                  (sb-bsd-sockets:socket-connect socket (host-to-vector-quad host) port)
                  (setf (connected-p usocket) t)))))
           (setf ok t))
      ;; Clean up in case of an error.
      (unless ok
        (sb-bsd-sockets:socket-close socket :abort t)))
    usocket))

(defun socket-listen (host port
                           &key reuseaddress
                           (reuse-address nil reuse-address-supplied-p)
                           (backlog 5)
                           (element-type 'character))
  (let* ((reuseaddress (if reuse-address-supplied-p reuse-address reuseaddress))
         (ip (host-to-vector-quad host))
         (sock (make-instance 'sb-bsd-sockets:inet-socket
                              :type :stream :protocol :tcp)))
    (handler-case
        (with-mapped-conditions ()
          (setf (sb-bsd-sockets:sockopt-reuse-address sock) reuseaddress)
          (sb-bsd-sockets:socket-bind sock ip port)
          (sb-bsd-sockets:socket-listen sock backlog)
          (make-stream-server-socket sock :element-type element-type))
      (t (c)
        ;; Make sure we don't leak filedescriptors
        (sb-bsd-sockets:socket-close sock)
        (error c)))))

(defmethod socket-accept ((socket stream-server-usocket) &key element-type)
  (with-mapped-conditions (socket)
     (let ((sock (sb-bsd-sockets:socket-accept (socket socket))))
       (make-stream-socket
        :socket sock
        :stream (sb-bsd-sockets:socket-make-stream
                 sock
                 :input t :output t :buffering :full
                 :element-type (or element-type
                                   (element-type socket)))))))

;; Sockets and their associated streams are modelled as
;; different objects. Be sure to close the stream (which
;; closes the socket too) when closing a stream-socket.
(defmethod socket-close ((usocket usocket))
  (when (wait-list usocket)
     (remove-waiter (wait-list usocket) usocket))
  (with-mapped-conditions (usocket)
    (sb-bsd-sockets:socket-close (socket usocket))))

(defmethod socket-close ((usocket stream-usocket))
  (when (wait-list usocket)
     (remove-waiter (wait-list usocket) usocket))
  (with-mapped-conditions (usocket)
    (close (socket-stream usocket))))

(defmethod socket-send ((socket datagram-usocket) buffer length &key host port)
  (with-mapped-conditions (socket)
    (let* ((s (socket socket))
           (dest (if (and host port) (list (host-to-vector-quad host) port) nil)))
      (sb-bsd-sockets:socket-send s buffer length :address dest))))

(defmethod socket-receive ((socket datagram-usocket) buffer length
			   &key (element-type '(unsigned-byte 8)))
  (with-mapped-conditions (socket)
    (let ((s (socket socket)))
      (sb-bsd-sockets:socket-receive s buffer length :element-type element-type))))

(defmethod get-local-name ((usocket usocket))
  (sb-bsd-sockets:socket-name (socket usocket)))

(defmethod get-peer-name ((usocket stream-usocket))
  (sb-bsd-sockets:socket-peername (socket usocket)))

(defmethod get-local-address ((usocket usocket))
  (nth-value 0 (get-local-name usocket)))

(defmethod get-peer-address ((usocket stream-usocket))
  (nth-value 0 (get-peer-name usocket)))

(defmethod get-local-port ((usocket usocket))
  (nth-value 1 (get-local-name usocket)))

(defmethod get-peer-port ((usocket stream-usocket))
  (nth-value 1 (get-peer-name usocket)))

(defun get-host-by-address (address)
  (with-mapped-conditions ()
    (sb-bsd-sockets::host-ent-name
        (sb-bsd-sockets:get-host-by-address address))))

(defun get-hosts-by-name (name)
  (with-mapped-conditions ()
     (sb-bsd-sockets::host-ent-addresses
         (sb-bsd-sockets:get-host-by-name name))))

#+(and sbcl (not win32))
(progn
  (defun %setup-wait-list (wait-list)
    (declare (ignore wait-list)))

  (defun %add-waiter (wait-list waiter)
    (push (socket waiter) (wait-list-%wait wait-list)))

  (defun %remove-waiter (wait-list waiter)
    (setf (wait-list-%wait wait-list)
          (remove (socket waiter) (wait-list-%wait wait-list))))

  (defun wait-for-input-internal (sockets &key timeout)
    (with-mapped-conditions ()
      (sb-alien:with-alien ((rfds (sb-alien:struct sb-unix:fd-set)))
         (sb-unix:fd-zero rfds)
         (dolist (socket (wait-list-%wait sockets))
           (sb-unix:fd-set
            (sb-bsd-sockets:socket-file-descriptor socket)
            rfds))
         (multiple-value-bind
             (secs musecs)
             (split-timeout (or timeout 1))
           (multiple-value-bind
               (count err)
               (sb-unix:unix-fast-select
                (1+ (reduce #'max (wait-list-%wait sockets)
                            :key #'sb-bsd-sockets:socket-file-descriptor))
                (sb-alien:addr rfds) nil nil
                (when timeout secs) (when timeout musecs))
	     (if (null count)
		 (unless (= err sb-unix:EINTR)
		   (error (map-errno-error err)))
		 (when (< 0 count)
		   ;; process the result...
                   (dolist (x (wait-list-waiters sockets))
                     (when (sb-unix:fd-isset
                            (sb-bsd-sockets:socket-file-descriptor
                             (socket x))
                            rfds)
                       (setf (state x) :READ))))))))))
) ; progn

;;; WAIT-FOR-INPUT support for SBCL on Windows platform (Chun Tian (binghe))
;;; Based on LispWorks version written by Erik Huelsmann.

#+win32 ; shared by ECL and SBCL
(progn
  (defconstant +wsa-wait-failed+ #xffffffff)
  (defconstant +wsa-wait-event-0+ 0)
  (defconstant +wsa-wait-timeout+ 258)

  (defconstant fd-read 1)
  (defconstant fd-read-bit 0)
  (defconstant fd-write 2)
  (defconstant fd-write-bit 1)
  (defconstant fd-oob 4)
  (defconstant fd-oob-bit 2)
  (defconstant fd-accept 8)
  (defconstant fd-accept-bit 3)
  (defconstant fd-connect 16)
  (defconstant fd-connect-bit 4)
  (defconstant fd-close 32)
  (defconstant fd-close-bit 5)
  (defconstant fd-qos 64)
  (defconstant fd-qos-bit 6)
  (defconstant fd-group-qos 128)
  (defconstant fd-group-qos-bit 7)
  (defconstant fd-routing-interface 256)
  (defconstant fd-routing-interface-bit 8)
  (defconstant fd-address-list-change 512)
  (defconstant fd-address-list-change-bit 9)
  (defconstant fd-max-events 10)
  (defconstant fionread 1074030207)

  ;; Note: for ECL, socket-handle will return raw Windows Handle,
  ;;       while SBCL returns OSF Handle instead.
  (defun socket-handle (usocket)
    (sb-bsd-sockets:socket-file-descriptor (socket usocket)))

  (defun socket-ready-p (socket)
    (if (typep socket 'stream-usocket)
        (plusp (bytes-available-for-read socket))
      (%ready-p socket)))

  (defun waiting-required (sockets)
    (notany #'socket-ready-p sockets))
) ; progn

#+(and sbcl win32)
(progn
  (sb-alien:define-alien-type ws-socket sb-alien:unsigned-int)
  (sb-alien:define-alien-type ws-dword sb-alien:unsigned-long)
  (sb-alien:define-alien-type ws-event sb-alien::hinstance)

  (sb-alien:define-alien-type nil
    (sb-alien:struct wsa-network-events
      (network-events sb-alien:long)
      (error-code (array sb-alien:int 10)))) ; 10 = fd-max-events

  (sb-alien:define-alien-routine ("WSACreateEvent" wsa-event-create)
      ws-event) ; return type only

  (sb-alien:define-alien-routine ("WSAResetEvent" wsa-event-reset)
      (boolean #.sb-vm::n-machine-word-bits)
    (event-object ws-event))

  (sb-alien:define-alien-routine ("WSACloseEvent" wsa-event-close)
      (boolean #.sb-vm::n-machine-word-bits)
    (event-object ws-event))

  (sb-alien:define-alien-routine ("WSAEnumNetworkEvents" wsa-enum-network-events)
      sb-alien:int
    (socket ws-socket)
    (event-object ws-event)
    (network-events (* (sb-alien:struct wsa-network-events))))

  (sb-alien:define-alien-routine ("WSAEventSelect" wsa-event-select)
      sb-alien:int
    (socket ws-socket)
    (event-object ws-event)
    (network-events sb-alien:long))

  (sb-alien:define-alien-routine ("WSAWaitForMultipleEvents" wsa-wait-for-multiple-events)
      ws-dword
    (number-of-events ws-dword)
    (events (* ws-event))
    (wait-all-p (boolean #.sb-vm::n-machine-word-bits))
    (timeout ws-dword)
    (alertable-p (boolean #.sb-vm::n-machine-word-bits)))

  (sb-alien:define-alien-routine ("ioctlsocket" wsa-ioctlsocket)
      sb-alien:int
    (socket ws-socket)
    (cmd sb-alien:long)
    (argp (* sb-alien:unsigned-long)))

  (defun raise-usock-err (errno socket)
    (error 'unknown-error
           :socket socket
           :real-error errno))

  (defun maybe-wsa-error (rv &optional socket)
    (unless (zerop rv)
      (raise-usock-err (sockint::wsa-get-last-error) socket)))

  (defun os-socket-handle (usocket)
    (sockint::fd->handle (sb-bsd-sockets:socket-file-descriptor (socket usocket))))

  (defun bytes-available-for-read (socket)
    (sb-alien:with-alien ((int-ptr sb-alien:unsigned-long))
      (maybe-wsa-error (wsa-ioctlsocket (os-socket-handle socket) fionread (sb-alien:addr int-ptr))
                       socket)
      int-ptr))

  (defun wait-for-input-internal (wait-list &key timeout)
    (when (waiting-required (wait-list-waiters wait-list))
      (let ((rv (wsa-wait-for-multiple-events 1 (wait-list-%wait wait-list)
                                              nil (truncate (* 1000 timeout)) nil)))
        (ecase rv
          ((#.+wsa-wait-event-0+ #.+wsa-wait-timeout+)
           (update-ready-and-state-slots (wait-list-waiters wait-list)))
          ((#.+wsa-wait-failed+)
           (raise-usock-err
            (sb-win32::get-last-error-message (sb-win32::get-last-error))
            wait-list))))))

  (defun map-network-events (func network-events)
    (let ((event-map (sb-alien:slot network-events 'network-events))
          (error-array (sb-alien:slot network-events 'error-code)))
      (unless (zerop event-map)
        (dotimes (i fd-max-events)
          (unless (zerop (ldb (byte 1 i) event-map)) ;;### could be faster with ash and logand?
            (funcall func (sb-alien:deref error-array i)))))))

  (defun update-ready-and-state-slots (sockets)
    (dolist (socket sockets)
      (if (or (and (stream-usocket-p socket)
                   (listen (socket-stream socket)))
              (%ready-p socket))
          (setf (state socket) :READ)
        (sb-alien:with-alien ((network-events (sb-alien:struct wsa-network-events)))
          (let ((rv (wsa-enum-network-events (os-socket-handle socket) 0
                                             (sb-alien:addr network-events))))
            (if (zerop rv)
                (map-network-events #'(lambda (err-code)
                                        (if (zerop err-code)
                                            (setf (%ready-p socket) t
                                                  (state socket) :READ)
                                          (raise-usock-err err-code socket)))
                                    network-events)
              (maybe-wsa-error rv socket)))))))

  (defun os-wait-list-%wait (wait-list)
    (sb-alien:deref (wait-list-%wait wait-list)))

  (defun (setf os-wait-list-%wait) (value wait-list)
    (setf (sb-alien:deref (wait-list-%wait wait-list)) value))

  (defun %setup-wait-list (wait-list)
    (setf (wait-list-%wait wait-list) (sb-alien:make-alien ws-event))
    (setf (os-wait-list-%wait wait-list) (wsa-event-create))
    (sb-ext:finalize wait-list
                     #'(lambda () (unless (null (wait-list-%wait wait-list))
                                    (wsa-event-close (os-wait-list-%wait wait-list))
                                    (sb-alien:free-alien (wait-list-%wait wait-list))))))

  (defun %add-waiter (wait-list waiter)
    (let ((events (etypecase waiter
                    (stream-server-usocket (logior fd-connect fd-accept fd-close))
                    (stream-usocket (logior fd-read))
                    (datagram-usocket (logior fd-read)))))
      (maybe-wsa-error
       (wsa-event-select (os-socket-handle waiter) (os-wait-list-%wait wait-list) events)
       waiter)))

  (defun %remove-waiter (wait-list waiter)
    (maybe-wsa-error
     (wsa-event-select (os-socket-handle waiter) (os-wait-list-%wait wait-list) 0)
     waiter))
) ; progn

#+(and ecl (not win32))
(progn
  (defun wait-for-input-internal (wl &key timeout)
    (with-mapped-conditions ()
      (multiple-value-bind
            (secs usecs)
          (split-timeout (or timeout 1))
        (multiple-value-bind
              (result-fds err)
            (read-select wl (when timeout secs) usecs)
          (unless (null err)
            (error (map-errno-error err)))))))

  (defun %setup-wait-list (wl)
    (setf (wait-list-%wait wl)
          (fdset-alloc)))

  (defun %add-waiter (wl w)
    (declare (ignore wl w)))

  (defun %remove-waiter (wl w)
    (declare (ignore wl w)))
) ; progn

#+(and ecl win32)
(progn
  (defun maybe-wsa-error (rv &optional syscall)
    (unless (zerop rv)
      (sb-bsd-sockets::socket-error syscall)))

  (defun %setup-wait-list (wl)
    (setf (wait-list-%wait wl)
          (ffi:c-inline () () :int
           "WSAEVENT event;
            event = WSACreateEvent();
            @(return) = event;")))

  (defun %add-waiter (wait-list waiter)
    (let ((events (etypecase waiter
                    (stream-server-usocket (logior fd-connect fd-accept fd-close))
                    (stream-usocket (logior fd-read))
                    (datagram-usocket (logior fd-read)))))
      (maybe-wsa-error
       (ffi:c-inline ((socket-handle waiter) (wait-list-%wait wait-list) events)
                     (:fixnum :fixnum :fixnum) :fixnum
        "int result;
         result = WSAEventSelect((SOCKET)#0, (WSAEVENT)#1, (long)#2);
         @(return) = result;")
       '%add-waiter)))

  (defun %remove-waiter (wait-list waiter)
    (maybe-wsa-error
     (ffi:c-inline ((socket-handle waiter) (wait-list-%wait wait-list))
                   (:fixnum :fixnum) :fixnum
      "int result;
       result = WSAEventSelect((SOCKET)#0, (WSAEVENT)#1, 0L);
       @(return) = result;")
     '%remove-waiter))

  ;; TODO: how to handle error (result) in this call?
  (defun bytes-available-for-read (socket)
    (ffi:c-inline ((socket-handle socket)) (:fixnum) :fixnum
     "u_long nbytes;
      int result;
      nbytes = 0L;
      result = ioctlsocket((SOCKET)#0, FIONREAD, &nbytes);
      @(return) = nbytes;"))

  (defun update-ready-and-state-slots (sockets)
    (dolist (socket sockets)
      (if (or (and (stream-usocket-p socket)
                   (listen (socket-stream socket)))
              (%ready-p socket))
          (setf (state socket) :READ)
        (let ((events (etypecase socket
                        (stream-server-usocket (logior fd-connect fd-accept fd-close))
                        (stream-usocket (logior fd-read))
                        (datagram-usocket (logior fd-read)))))
          ;; TODO: check the iErrorCode array
          (if (ffi:c-inline ((socket-handle socket) events) (:fixnum :fixnum) :bool
               "WSANETWORKEVENTS network_events;
                int i, result;
                result = WSAEnumNetworkEvents((SOCKET)#0, 0, &network_events);
                if (!result) {
                  @(return) = (#1 & network_events.lNetworkEvents)? Ct : Cnil;
                } else
                  @(return) = Cnil;")
              (setf (%ready-p socket) t
                    (state socket) :READ)
            (sb-bsd-sockets::socket-error 'update-ready-and-state-slots))))))

  (defun wait-for-input-internal (wait-list &key timeout)
    (when (waiting-required (wait-list-waiters wait-list))
      (let ((rv (ffi:c-inline ((wait-list-%wait wait-list) (truncate (* 1000 timeout)))
                              (:fixnum :fixnum) :fixnum
                 "DWORD result;
                  WSAEVENT events[1];
                  events[0] = (WSAEVENT)#0;
                  result = WSAWaitForMultipleEvents(1, events, NULL, #1, NULL);
                  @(return) = result;")))
        (ecase rv
          ((#.+wsa-wait-event-0+ #.+wsa-wait-timeout+)
           (update-ready-and-state-slots (wait-list-waiters wait-list)))
          ((#.+wsa-wait-failed+)
           (sb-bsd-sockets::socket-error 'wait-for-input-internal))))))

) ; progn
