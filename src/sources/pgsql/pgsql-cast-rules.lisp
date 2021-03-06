;;;
;;; Tools to handle PostgreSQL data type casting rules
;;;

(in-package :pgloader.source.pgsql)

(defparameter *pgsql-default-cast-rules*
  '((:source (:type "integer" :auto-increment t)
     :target (:type "serial" :drop-default t))

    (:source (:type "bigint" :auto-increment t)
     :target (:type "bigserial" :drop-default t))

    (:source (:type "character varying")
     :target (:type "text" :drop-typemod t)))
  "Data Type Casting to migrate from PostgtreSQL to PostgreSQL")

(defmethod pgsql-column-ctype ((column column))
  "Build the ctype definition from the PostgreSQL column information."
  (let ((type-name (column-type-name column))
        (type-mod  (unless (or (null (column-type-mod column))
                               (eq :null (column-type-mod column)))
                     (column-type-mod column))))
    (format nil "~a~@[(~a)~]" type-name type-mod)))

(defmethod cast ((field column) &key &allow-other-keys)
  "Return the PostgreSQL type definition from the given PostgreSQL column
   definition"
  (with-slots (pgloader.catalog::name
               pgloader.catalog::type-name
               pgloader.catalog::type-mod
               pgloader.catalog::nullable
               pgloader.catalog::default
               pgloader.catalog::comment
               pgloader.catalog::transform
               pgloader.catalog::extra)
      field
    (let* ((ctype (pgsql-column-ctype field))
           (pgcol (apply-casting-rules nil
                                       pgloader.catalog::name
                                       pgloader.catalog::type-name
                                       ctype
                                       pgloader.catalog::default
                                       pgloader.catalog::nullable
                                       pgloader.catalog::extra)))
      ;; re-install our instruction not to transform default value: it comes
      ;; from PostgreSQL, and we trust it.
      (setf (column-transform-default pgcol)
            (column-transform-default field))

      ;; Redshift may be using DEFAULT getdate() instead of now()
      (let ((default (column-default pgcol)))
        (setf (column-default pgcol)
              (cond
                ((and (stringp default) (string= "NULL" default))
                 :null)

                ((and (stringp default)
                      (or (string= "getdate()" default)))
                 :current-timestamp)

                (t (column-default pgcol))))

        ;; we usually trust defaults that come from PostgreSQL... but we
        ;; also have support for Redshift.
        (when (member (column-default pgcol) '(:null :current-timestamp))
          (setf (column-transform-default pgcol) t)))

      pgcol)))
