(in-package #:cl-user)
(uiop:define-package utopian/tasks
  (:mix #:cl
        #:lake
        #:clack
        #:mito
        #:utopian/app
        #:utopian/watcher
        #:utopian/config
        #:utopian/db
        #:uiop)
  (:export #:load-tasks))
(in-package #:utopian/tasks)

(defun connect-to-db ()
  (apply #'mito:connect-toplevel (connection-settings :maindb)))

(defun load-models ()
  (dolist (model-file (uiop:directory-files (project-path "models/") "*.lisp"))
    (funcall #+quicklisp #'ql:quickload
             #-quicklisp #'asdf:load-system
             (format nil "~A/models/~A"
                     (project-name)
                     (pathname-name model-file)))))

(defun task-migrate ()
  (mito:migrate (project-path "db/")))

(defun task-generate-migrations ()
  (mito:generate-migrations (project-path "db/")))

(defun load-tasks ()
  (task "default" ("server"))

  (task "server" ()
    (clack:clackup (project-path #P"app.lisp")
                   :use-thread nil
                   :debug (not (productionp))))

  (namespace "db"
    (task "migrate" ()
      (connect-to-db)
      (load-models)
      (task-migrate))
    (task "generate-migrations" ()
      (connect-to-db)
      (load-models)
      (task-generate-migrations))
    (task "seed" ()
      (connect-to-db)
      (let ((seeds (project-path #P"db/seeds.lisp")))
        (unless (probe-file seeds)
          (error "'db/seeds.lisp' doesn't exist."))
        (mito.logger:with-sql-logging
          (load seeds))))
    (task "recreate" ()
      (apply #'mito:connect-toplevel
             (car (connection-settings :maindb))
             :database-name "postgres"
             (alexandria:remove-from-plist
              (cdr (connection-settings :maindb))
              :database-name))
      (let ((dbname (getf (cdr (connection-settings :maindb)) :database-name)))
        (mito:execute-sql
         (format nil "DROP DATABASE \"~A\"" dbname))
        (mito:execute-sql
         (format nil "CREATE DATABASE \"~A\"" dbname)))
      (mapc #'delete-file (uiop:directory-files (project-path #P"db/migrations/")))
      (connect-to-db)
      (load-models)
      (task-generate-migrations)
      (task-migrate))))
