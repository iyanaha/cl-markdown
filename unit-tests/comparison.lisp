(in-package cl-markdown-test)

(defvar *errors* nil)
(defvar *all-wells* nil)

(defparameter *test-source-directory* 
  (system-relative-path
   'cl-markdown 
   (make-pathname :directory ";unit-tests;markdown-tests;")))

(defparameter *test-output-directory*
  (system-relative-path
   'cl-markdown 
   (make-pathname :directory ";website;output;comparison-tests;")))

(defun compare-markdown-and-cl-markdown (basename)
  (cl-markdown-and-tidy basename)
  (markdown-and-tidy basename)
  (create-comparison-file basename))   

(defun create-main-comparison-page ()
  (let ((output (make-pathname :type "html"
                               :name "index"
                               :defaults *test-output-directory*)))
    (ensure-directories-exist output)
    (with-new-file (s output)
      (lml2:html-stream 
       s
       (lml2:html
        (:head (:title "Index | CL-Markdown / Markdown Comparison")
               ((:link :rel "stylesheet" :href "style.css")))
        (:body
         ((:div :id "contents")
          (:P 
           "Below are the results of running "
           ((:A :href "http://www.common-lisp.net/project/cl-markdown") "CL-Markdown")
           " and the Perl " ((:a :href "http://www.daringfireball.net/markdown") "Markdown") 
           " script on the same input. You'll see that the current version of CL-Markdown performs OK on a few 
documents, very poorly on others and not at all on some.")
          (:P "Sometimes, CL-Markdown produces invalid HTML. Most browsers will still display the output but "
              ((:A :href "tidy") "Tidy") " reports errors and produces no output. This will show up as a blank section on the comparison page")
          (:P 
           "This will be updated regularly. The most recent update was "
           (lml2:lml-princ (format-date "%e %B %Y" (get-universal-time))))

          (:H2 "Comparison Tests")
          (:P "Files in red had Lisp errors during the run.")
          (:P "Files in green had no differences from Markdown output during the run.")
          
          (iterate-elements 
           (directory 
            (make-pathname :name :wild :type "text" :defaults *test-source-directory*))
           (lambda (file)
             (let* ((entry-file (comparison-file-name (pathname-name file)))
                    (entry (namestring (make-pathname :name (pathname-name entry-file)
                                                      :type "html"))))
               (lml2:html
                ((:span :class 
                        (cond ((find (pathname-name file) *errors* :test #'string-equal)
                               "error-entry")
                              ((find (pathname-name file) *all-wells* :test #'string-equal)
                               "no-diff-entry")
                              (t "index-entry")))
                 ((:a :href entry) (lml2:lml-princ entry)))))))
          ((:div :id "footer") "end 'o page"))))))))

(defun compare-all ()
  (iterate-elements 
   (directory (make-pathname :name :wild :type "text" :defaults *test-source-directory*))
   (lambda (file)
     (handler-case
       (compare-markdown-and-cl-markdown (pathname-name file))
       (error (c) 
              (push (pathname-name file) *errors*)
              (create-error-file (pathname-name file) c)))))
  (create-main-comparison-page))

(defun cl-markdown-and-tidy (basename)
  (let* ((inpath (make-pathname :type "text"
                                :name basename 
                                :defaults *test-source-directory*))
         (output (make-pathname :type "html"
                                :name basename
                                :defaults *test-source-directory*)))
    (cl-markdown::render-to-stream (markdown inpath) :html output)
    (tidy basename "html" "xxxx")
    output))

(defun create-error-file (basename condition)
  (let ((output (comparison-file-name basename)))
    (ensure-directories-exist output)
    (with-new-file (s output)
      (lml2:html-stream 
       s
       (lml2:html
        (:head (:title "CL-Markdown / Markdown Comparison")
               ((:link :rel "stylesheet" :href "style.css")))
        (:body
         ((:div :id "contents")
          (:P "Error during parsing of '" (lml2:lml-princ basename) "'.")
          ((:a :href "index.html") "Back to index")
          (:P 
           (:pre
            (lml2:lml-princ
             (html-encode:encode-for-pre 
              (html-encode:encode-for-http
               (format nil "~A" condition))))))
          
          (:div
           ((:div :id "original-source")
            (:h1 "Original source")
            ((:div :class "section-contents")
             (:pre
              (lml2:lml-princ
               (html-encode:encode-for-pre 
                (file->string (make-pathname 
                               :type "text"
                               :name basename 
                               :defaults *test-source-directory*))))))))
          ((:div :id "footer") "end 'o page"))))))))

(defun markdown-and-tidy (basename)
  (let* ((inpath (make-pathname :type "text"
                                :name basename 
                                :defaults *test-source-directory*))
         (outpath (make-pathname :type "mark"
                                 :name basename 
                                 :defaults *test-source-directory*)))
    (metashell:shell-command 
     (format nil "/usr/local/bin/markdown '~a' > '~A'"
             (system-namestring inpath) (system-namestring outpath)))
    
    (tidy basename "mark" "down")
    outpath))

(defun tidy (basename input-type output-type)
  (let* ((inpath (make-pathname :type input-type
                                :name basename 
                                :defaults *test-source-directory*))
         (tidy-output (make-pathname :type output-type
                                     :name basename 
                                     :defaults *test-source-directory*))
         (command (format nil 
                          "/usr/bin/tidy --show-body-only 1 --quiet 1 --show-warnings 0 '~A' > '~A'"
                          (system-namestring inpath)
                          (system-namestring tidy-output))))
    (metashell:shell-command command)
    (when (zerop (kl:file-size tidy-output))
      ;; an error in the HTML
      (warn "HTML Error for ~A" basename))
    tidy-output))

(defun comparison-file-name (basename)
  (make-pathname :defaults *test-output-directory*
                 :type "html"
                 :name (concatenate 'string basename "-compare")))

(defun create-comparison-file (basename)
  (bind ((cl-file (make-pathname :type "xxxx"
                                 :name basename 
                                 :defaults *test-source-directory*))
         (md-file (make-pathname :type "down"
                                 :name basename 
                                 :defaults *test-source-directory*))
         ((values diff nil replace insert delete)
          (html-diff::html-diff (file->string md-file) (file->string cl-file)))
         (output (comparison-file-name basename)))
    (ensure-directories-exist output)
    (with-new-file (s output)
      (lml2:html-stream 
       s
       (lml2:html
        (:head (:title "CL-Markdown / Markdown Comparison")
               ((:link :rel "stylesheet" :href "style.css")))
        (:body
         ((:div :id "contents")
          
          ((:div :id "header")
           (:h1 "File: " (lml2:lml-princ basename) ".text"))
          ((:a :href "index.html") "Back to index")
          (:div
           ((:div :id "cl-markdown-output")
            (:h1 "CL-Markdown")
            ((:div :class "section-contents")
             (lml2:insert-file cl-file)))
           
           ((:div :id "markdown-output")
            (:h1 "Markdown")
            ((:div :class "section-contents")
             (lml2:insert-file md-file))))
          
          (:div
           ((:div :id "diff-output")
            (:h1 "HTML Difference")
            ((:div :class "section-contents")
             (cond ((and (zerop insert) (zerop delete) (zerop replace))
                    (push basename *all-wells*)
                    (lml2:lml-princ "No differences"))
                   (t
                    (lml2:html
                     (:P 
                      "Insert: " (lml2:lml-princ insert)
                      ", Delete: " (lml2:lml-princ delete)
                      ", Replace " (lml2:lml-princ replace))
                     
                     (lml2:lml-princ
                      diff))))))
           
           ((:div :id "cl-markdown-html")
            (:h1 "HTML from CL Markdown")
            ((:div :class "section-contents")
             (:pre
              (lml2:lml-princ
               (html-encode:encode-for-pre 
                (html-encode:encode-for-http
                 (file->string cl-file))))))))
          
          (:div
           ((:div :id "original-source")
            (:h1 "Original source")
            ((:div :class "section-contents")
             (:pre
              (lml2:lml-princ
               (html-encode:encode-for-pre 
                (html-encode:encode-for-http
                 (file->string (make-pathname :type "text"
                                              :name basename 
                                              :defaults *test-source-directory*)))))))))
          ((:div :id "footer") "end 'o page"))))))))

(defun file->string (pathname)
  (apply 'concatenate 
         'string
         (with-iterator (iterator (make-pathname :defaults pathname) 
                                  :treat-contents-as :lines 
                                  :skip-empty-chunks? nil) 
           (collect-elements
            iterator
            :transform (lambda (line) 
                         (format nil "~%~A" line))))))

#|


(render-to-stream 
 (markdown #P"Billy-Pilgrim:Users:gwking:darcs:cl-markdown:unit-tests:markdown-tests:Ordered and unordered lists.text")
 :lml2 :none)

(render-to-stream 
 (markdown #P"Billy-Pilgrim:Users:gwking:darcs:cl-markdown:unit-tests:markdown-tests:Nested blockquotes.text")
 :lml2 :none)

Nested blockquotes
(markdown-tidy "Horizontal rules")
(markdown-tidy "Ordered and unordered lists")

(markdown-tidy "bullets-and-numbers-1")

(markdown-and-tidy "bullets-and-numbers-1")
(cl-markdown-and-tidy "bullets-and-numbers-1")

(metashell:shell-command "/usr/bin/tidy --show-body-only 1 --quiet 1 --show-warnings 0 /Users/gwking/darcs/cl-markdown/unit-tests/markdown-tests/bullets-and-numbers-1.html > /Users/gwking/darcs/cl-markdown/unit-tests/markdown-tests/bullets-and-numbers-1.tidy")


|#