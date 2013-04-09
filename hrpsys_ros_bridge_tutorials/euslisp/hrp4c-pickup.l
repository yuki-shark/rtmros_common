(load "package://hrpsys_ros_bridge/euslisp/rtm-ros-robot-interface.l")
(require :hrp4c "package://hrpsys_ros_bridge_tutorials/models/hrp4c.l")

(defclass hrp4c-interface
  :super rtm-ros-robot-interface
  :slots ())
(defmethod hrp4c-interface
  (:init (&rest args)
   (prog1 (send-super :init :robot hrp4-robot)
     (send self :add-controller :larm-controller)
     (send self :add-controller :rarm-controller)
     (send self :add-controller :head-controller)
     (send self :add-controller :torso-controller)
     ))
  (:larm-controller ()
   (list
    (list
     (cons :controller-action "larm_controller/joint_trajectory_action")
     (cons :controller-state "larm_controller/state")
     (cons :action-type pr2_controllers_msgs::JointTrajectoryAction)
     (cons :joint-names (list "L_SHOULDER_P" "L_SHOULDER_R" "L_SHOULDER_Y" "L_ELBOW_P"
                              "L_WRIST_Y" "L_WRIST_R" "L_HAND_J0" "L_HAND_J1")))))
  (:rarm-controller ()
   (list
    (list
     (cons :controller-action "rarm_controller/joint_trajectory_action")
     (cons :controller-state "rarm_controller/state")
     (cons :action-type pr2_controllers_msgs::JointTrajectoryAction)
     (cons :joint-names (list "R_SHOULDER_P" "R_SHOULDER_R" "R_SHOULDER_Y" "R_ELBOW_P"
                              "R_WRIST_Y" "R_WRIST_R" "R_HAND_J0" "R_HAND_J1")))))
  (:head-controller ()
   (list
    (list
     (cons :controller-action "head_controller/joint_trajectory_action")
     (cons :controller-state "head_controller/state")
     (cons :action-type pr2_controllers_msgs::JointTrajectoryAction)
     (cons :joint-names (list "NECK_Y" "NECK_R" "NECK_P")))))
  (:torso-controller ()
   (list
    (list
     (cons :controller-action "torso_controller/joint_trajectory_action")
     (cons :controller-state "torso_controller/state")
     (cons :action-type pr2_controllers_msgs::JointTrajectoryAction)
     (cons :joint-names (list "CHEST_P" "CHEST_R" "CHEST_Y")))))
  )

(defun hrp4c-init ()
  (if (not (boundp '*ri*))
      (setq *ri* (instance hrp4c-interface :init)))
  (if (not (boundp '*hrp4c*))
      (setq *hrp4c* (instance hrp4-robot :init)))
  (send *hrp4c* :reset-pose)
  ;; send reset pose to real robot
  (send *ri* :angle-vector (send *hrp4c* :angle-vector) 3000)
  (send *ri* :wait-interpolation)
  )

(defun hrp4c-walk ()
  (let ((eof (gensym)) avs av tms tm (tmp 0) s l)
    (with-open-file
     (f (ros::resolve-ros-path "package://hrpsys/share/hrpsys/samples/HRP4C/data/walk2m.pos") :direction :input)
     (while (not (eq (setq l (read-line f nil eof)) eof))
       (setq s (make-string-input-stream l))
       (setq tm (* 1000 (read s)))
       (setq av nil)
       (while (not (eq (setq n (read s nil eof)) eof))
	 (push (rad2deg n) av)
	 )
       ;; :angle-vector-sequence version
       ;;(setq av (reverse av))
       ;;(setq av (concatenate float-vector (subseq av 0 6) (subseq av 7 12) (subseq av 13)))

       ;; :angle-vector-for-seq-debug version
       (setq av (concatenate float-vector (reverse av)))

       (push av avs)
       (push (- (round tm) (round tmp)) tms)
       (setq tmp tm)
       )
     (setq avs (reverse avs))
     (setq tms (reverse tms))
     )
    (send *ri* :set-interpolation-mode :linear)
    ;; :angle-vector-for-seq-debug version
    ;;(send *ri* :angle-vector-sequence avs tms)

    ;; :angle-vector-for-seq-debug version
    (let ((avs2) (tms2) (sendcount 5)) ;; sendcount <- down sampling
      (push (car avs) avs2)
      (push (car tms) tms2)
      (dotimes (i (length avs))
	(when (and (= (mod i sendcount) 0) (> i 0))
	  (push (elt avs i) avs2)
	  (push (* sendcount (elt tms i)) tms2)))
      (setq avs (reverse avs2))
      (setq tms (reverse tms2))
      (mapcar
       #'(lambda (av tm)
      	   (send *ri* :angle-vector-for-seq-debug av tm)
      	   (send *ri* :wait-interpolation-for-seq-debug))
       avs tms))

    (send *ri* :wait-interpolation)
    (send *ri* :set-interpolation-mode :hoffarbib)
    ))


(defun hrp4c-lookdown ()
  ;; reset manip pose
  (send *hrp4c* :torso :waist-y :joint-angle -30)
  (send *hrp4c* :arms :shoulder-p :joint-angle 40)
  (send *hrp4c* :arms :elbow-p :joint-angle -90)
  (send *hrp4c* :head :neck-p :joint-angle -30)
  (send *ri* :angle-vector (send *hrp4c* :angle-vector) 3000)
  (send *ri* :wait-interpolation)
  )

(defun hrp4c-pickup ()
  (send *hrp4c* :inverse-kinematics
	(make-coords :pos #f(400 -200 600))
	:link-list (send *hrp4c* :link-list (send *hrp4c* :rarm :end-coords :parent))
	:move-target (send *hrp4c* :rarm :end-coords)
	:rotation-axis nil
	:look-at-target t
	:debug-view t)
  (send *ri* :angle-vector (send *hrp4c* :angle-vector) 3000)
  (send *ri* :wait-interpolation)
  )

(defun hrp4c-fullbody-pickup ()
  (let* ((limbs '(:rarm :rleg :lleg))
         (move-target (mapcar #'(lambda (l) (send *hrp4c* l :end-coords)) limbs))
         (link-list (mapcar #'(lambda (mt)
                                (send *hrp4c* :link-list (send mt :parent)))
                            move-target))
         (fix-leg-coords (list (send *hrp4c* :rleg :end-coords :copy-worldcoords)
                               (send *hrp4c* :lleg :end-coords :copy-worldcoords))))
    (send *hrp4c* :reset-pose)
    ;; fullbody-inverse-kinematics requires parameters for rarm, rleg, and lleg
    (send *hrp4c* :fullbody-inverse-kinematics
          (append (list (make-coords :pos #f(250 -200 170))) fix-leg-coords)
          :link-list link-list :move-target move-target
          :rotation-axis (list nil t t) :thre '(5 1 1)
          :look-at-target t
          :cog-gain 2.5 :stop 200 :centroid-thre 20
          :debug-view t))
  (send *ri* :angle-vector (send *hrp4c* :angle-vector) 3000)
  (send *ri* :wait-interpolation)
  )

(ros::roseus "hrp4c_pickup")
(hrp4c-init)
(hrp4c-walk)
(hrp4c-lookdown)
;(hrp4c-pickup)
(hrp4c-fullbody-pickup)
(hrp4c-init)
#|
;;
(send *hrp4c* :larm :angle-vector #f(-40.0 30 20 -40 20 0.0 0.0 0.0))
(send *ri* :angle-vector (send *hrp4c* :angle-vector) 3000 :larm-controller)
;;
(setq lst
(mapcar #'(lambda (v)
            (send *hrp4c* :larm :angle-vector v)
            (send *hrp4c* :angle-vector))
        (list #f(-40.0 30 20 -40 10 0.0 0.0 0.0)
              #f(-30.0 20 40 -20 20 0.0 0.0 0.0)
              #f(-20.0 10 20 -40 30 0.0 0.0 0.0))))
(send *ri* :angle-vector-sequence lst (list 1000 1000 1000) :larm-controller)
|#