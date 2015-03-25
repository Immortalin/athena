#-----------------------------------------------------------------------
# TITLE:
#    aam.tcl
#
# AUTHOR:
#    Will Duquette
#
# DESCRIPTION:
#    athena(n): Athena Attrition Model manager
#
#    This module is responsible for computing and applying attrition
#    to units and neighborhood groups.
#
#    As attrition tactics execute, a list of attrition dictionaries
#    is accumulated by this module.  When the assess method is called
#    the attrition data is extracted from this list and applied.  For 
#    civilian casualties, satisfaction and cooperation dictionaries 
#    are built up and then passed into the CIVCAS rule set where the 
#    effects are applied.
#
#    The satisfaction and cooperation dictionaries are entirely 
#    transient. They only exist for the purpose of storing the data 
#    needed by the CIVCAS rule set.  The dictionaries are created, 
#    used and deleted within the assess method.
#
# Global references: demog, unit, group, personnel, ptype
#
#-----------------------------------------------------------------------

#-----------------------------------------------------------------------
# Module Singleton

snit::type ::athena::aam {
    #-------------------------------------------------------------------
    # Components

    component adb  ;# the athenadb(n) instance

    #-------------------------------------------------------------------
    # Constructor

    # constructor adb_
    #
    # adb_    - The athenadb(n) that owns this instance
    #
    # Initializes instances of this type

    constructor {adb_} {
        set adb $adb_


    }

    #------------------------------------------------------------------
    # Variables

    variable alist {}   ;# list of attrition dictionaries
    variable sdict      ;# dict used to assess SAT effects
    variable cdict      ;# dict used to assess COOP effects
    variable frcmultD   ;# force multiplier denominator, same for all groups
    variable roedict    ;# array of dicts used to store ROE tactic information

    #-------------------------------------------------------------------
    # reset

    method reset {} {
        set alist ""
        set sdict ""
        set cdict ""
        array unset roedict
    }

    method start {} {
        # FIRST, clear out temporary table 
        $adb eval {
            DELETE FROM working_force;
        }

        # NEXT, compute force group multiplier denominator
        set urb   [$adb parm get aam.FRC.urbcas.URBAN]
        set civc  [$adb parm get aam.FRC.civconcern.NONE]
        set elvl  [$adb parm get aam.FRC.equiplevel.BEST]
        set ftype [$adb parm get aam.FRC.forcetype.REGULAR]
        set tlvl  [$adb parm get aam.FRC.discipline.PROFICIENT]
        set dem   [$adb parm get aam.FRC.demeanor.AVERAGE]
        let frcmultD {$urb * $civc * $elvl * $ftype * $tlvl * $dem}

        # NEXT, allocate forces and initialize group posture
        $self ComputeEffectiveForce
        $self BuildWorkingForceTable
        $self AllocateForce
        $self SetGroupPosture   
    }

    # ComputeEffectiveForce
    #
    # This method computes a deployed force groups effective force
    # based on it's makeup.  For example, highly disciplined regular 
    # forces with the best equipment will project more force than 
    # poorly trained irregular forces with poor equipment.

    method ComputeEffectiveForce {} {
        foreach {elvl tlvl frctype dem urb pers n g} [$adb eval {
            SELECT F.equip_level   AS equip_level,
                   F.training      AS training,
                   F.forcetype     AS forcetype,
                   F.demeanor      AS demeanor,
                   N.urbanization  AS urb,
                   D.personnel     AS personnel,
                   D.n             AS n,
                   D.g             AS g
            FROM gui_frcgroups AS F
            JOIN deploy_ng     AS D ON (D.g=F.g)
            JOIN nbhoods       AS N ON (D.n=N.n)
            WHERE D.personnel > 0
        }] {
            set Fe [$adb parm get aam.FRC.equiplevel.$elvl]
            set Ff [$adb parm get aam.FRC.forcetype.$frctype]
            set Ft [$adb parm get aam.FRC.discipline.$tlvl]
            set Fd [$adb parm get aam.FRC.demeanor.$dem]
            set Fu [$adb parm get aam.FRC.urbcas.$urb]

            let effForce {entier(ceil($Fe * $Ff * $Ft * $Fd * $pers))}
            let frcmult {$Fe * $Ff * $Ft * $Fd * $Fu}

            $adb eval {
                UPDATE deploy_ng
                SET eff_force = $effForce,
                    frcmult   = $frcmult 
                WHERE n=$n AND g=$g
            }
        }
    }

    # BuildWorkingForceTable
    #
    # This method builds the working combat table based on deployments.
    # Default ROEs, thresholds and postures are set for those groups
    # that have not explictly been given them via an actor's strategy.

    method BuildWorkingForceTable {} {
        # FIRST, get max combat time for this week
        set hours [$adb parm get aam.maxCombatTimeHours]

        # NEXT, fill in the working combat table based on
        # deployments
        foreach {n f pers_f eff_frc_f fmult_f} [$adb eval {
            SELECT n,g,personnel,eff_force,frcmult FROM deploy_ng 
            WHERE personnel>0
        }] {                       
            # NEXT, groups in n other than f
            foreach {g pers_g eff_frc_g fmult_g} [$adb eval {
                SELECT g,personnel,eff_force,frcmult FROM deploy_ng 
                WHERE n=$n AND personnel>0 AND g!=$f
            }] {
                # NEXT, defaults in case no ROE specified
                set roe  "DEFEND"
                set athr 0.0
                set dthr 0.15
                set civc "HIGH"

                # NEXT, pull data from ROE dict, if it's there 
                if {[info exists roedict($n)] && 
                    [dict exists $roedict($n) $f $g]} {
                    set roe  [dict get $roedict($n) $f $g roe]
                    set athr [dict get $roedict($n) $f $g athresh]
                    set dthr [dict get $roedict($n) $f $g dthresh]
                    set civc [dict get $roedict($n) $f $g civc]
                }

                # NEXT, compute force ratios used for determining posture
                # later 
                let frcRatio {
                    (double($eff_frc_g)/double($pers_g)) / 
                    (double($eff_frc_f)/double($pers_f))
                }

                let attack_R {$athr * $frcRatio}
                let defend_R {$dthr * $frcRatio}

                # NEXT, if a record for the pair of potential combatants
                # already exists, update it with g's data
                if {[$adb exists {
                    SELECT * FROM working_force
                    WHERE n=$n AND f=$g AND g=$f
                }]} {
                    $adb eval {
                        UPDATE working_force 
                        SET roe_g       = $roe,
                            civc_g      = $civc,
                            fmult_g     = $fmult_g,
                            attack_R_gf = $attack_R,
                            defend_R_gf = $defend_R
                        WHERE n=$n AND f=$g AND g=$f
                    }

                    continue
                }
                
                # NEXT, add to the working force table
                $adb eval {
                    INSERT INTO working_force(n,f,g,pers_f,pers_g,fmult_f,
                                              roe_f,attack_R_fg,defend_R_fg,
                                              civc_f,eff_frc_f,eff_frc_g,
                                              hours_left)
                    VALUES($n,$f,$g,$pers_f,$pers_g,$fmult_f,$roe,$attack_R,
                           $defend_R,$civc,$eff_frc_f,$eff_frc_g,$hours)
                }
            }
        }
    }

    # AllocateForce
    #
    # This method determines how many personnel in force group f
    # should be allocated against a force group g where either f is
    # attacking g or g is attacking f (or both).  Allocation is based
    # upon how much force is projected by the groups involved in combat.

    method AllocateForce {} {
        # FIRST, go through the working combat table looking for groups
        # that could possibly be in combat
        foreach {n f g} [$adb eval {
            SELECT n,f,g FROM working_force
            WHERE roe_f = 'ATTACK' OR roe_g = 'ATTACK'
        }] {
            # NEXT, compute total effective force from f's point of view
            # Those g's that f is attacking
            set totalEffFrcG [$adb eval {
                SELECT total(eff_frc_g) FROM working_force
                WHERE n=$n AND f=$f AND roe_f='ATTACK'
            }]

            # Those g's attacking f 
            set totalEffFrcF [$adb eval {
                SELECT total(eff_frc_g) FROM working_force
                WHERE n=$n AND f=$f AND roe_g='ATTACK'
            }]

            let totalFrcF {$totalEffFrcG + $totalEffFrcF}

            # NEXT, compute total effective force from g's point of view
            # Those g is attacking
            set totalEffFrcF [$adb eval {
                SELECT total(eff_frc_f) FROM working_force
                WHERE n=$n AND g=$g AND roe_g='ATTACK'
            }]

            # Those attacking g
            set totalEffFrcG [$adb eval {
                SELECT total(eff_frc_f) FROM working_force
                WHERE n=$n AND g=$g AND roe_f='ATTACK'
            }]


            let totalFrcG {$totalEffFrcG + $totalEffFrcF}

            # NEXT, allocate personnel based on effective force
            $adb eval {
                UPDATE working_force
                SET desig_pers_f = 
                        CAST(round(pers_f*eff_frc_g/$totalFrcF) AS INTEGER),
                    desig_pers_g = 
                        CAST(round(pers_g*eff_frc_f/$totalFrcG) AS INTEGER)
                WHERE n=$n AND f=$f AND g=$g
            }               
        }
    }

    # SetGroupPosture
    #
    # Based on designated personnel, ordered ROE and force/enemy ratios,
    # this method sets group posture for each group in the working force
    # table involved in combat

    method SetGroupPosture {} {
        $adb eval {
            SELECT * FROM working_force
            WHERE desig_pers_f > 0 AND desig_pers_g > 0
        } row {
            # FIRST, set default posture
            set posture_f "DEFEND"
            set posture_g "DEFEND"
            let DPf {double($row(desig_pers_f))}
            let DPg {double($row(desig_pers_g))}

            # NEXT, f's posture towards g, ATTACK only if ordered
            if {$DPf/$DPg >= $row(attack_R_fg) && $row(roe_f) eq "ATTACK"} {
                set posture_f "ATTACK"
            } elseif {$DPf/$DPg < $row(defend_R_fg)} {
                set posture_f "WITHDRAW"
            } 

            # NEXT, g's posture towards f, ATTACK only if ordered
            if {$DPg/$DPf >= $row(attack_R_gf) && $row(roe_g) eq "ATTACK"} {
                set posture_g "ATTACK"
            } elseif {$DPg/$DPf < $row(defend_R_gf)} {
                set posture_g "WITHDRAW"
            } 

            # NEXT, set posture in the adb
            $adb eval {
                UPDATE working_force
                SET posture_f = $posture_f,
                    posture_g = $posture_g
                WHERE n=$row(n) AND f=$row(f) AND g=$row(g)
            }
        }
    }

    # ComputeForceGroupAttrition
    #
    # This method goes through the working force table and computes
    # the amount of time two combatant fight based on postures and 
    # Lanchester attrition rates.  This time is used to compute the
    # number of casualties each side of a force on force fight
    # takes and updates the number of personnel engaged in combat.  
    # A flag indicating whether there is more fighting to be done is
    # returned.  Fighting ceases under these conditions:
    #
    #    * All personnel on one side are killed
    #    * Both force groups assume a posture for which fighting ceases
    #    * The amount of time exceeds the amount of time allocated for combat
    #
    # This method will return 1 if there is at least one pair of combatants
    # that do NOT meet any of these conditions and 0 otherwise.

    method ComputeForceGroupAttrition {} { 
        # FIRST, initialize transient combat outcome data
        set outcome [list] 

        # NEXT, go through active combat and assess
        $adb eval {
            SELECT * FROM working_force
            WHERE desig_pers_f > 0 AND 
                  desig_pers_g > 0 AND
                  hours_left   > 0 
        } row {
            # NEXT, get model parameter Lanchester coefficients 
            set afg [$adb parm get aam.lc.$row(posture_f).$row(posture_g)]
            set agf [$adb parm get aam.lc.$row(posture_g).$row(posture_f)]

            # NEXT, no assessment if no casualties will take place
            if {$afg == 0.0 && $agf == 0.0} {
                continue
            }

            # NEXT, combat time depends on posture and force ratio
            # thresholds
            set Rfg $row(attack_R_fg)
            set Rgf $row(attack_R_gf)

            if {$row(posture_f) eq "DEFEND"} {
                set Rfg $row(defend_R_fg)
            } elseif {$row(posture_f) eq "WITHDRAW"} {
                set Rfg 0.0
            }

            if {$row(posture_g) eq "DEFEND"} {
                set Rgf $row(defend_R_gf)
            } elseif {$row(posture_g) eq "WITHDRAW"} {
                set Rgf 0.0
            }

            # Coefficient multipliers for Afg
            set Fc [$adb parm get aam.FRC.civconcern.$row(civc_f)]
            let Afg {$afg * $Fc * $row(fmult_f) / $frcmultD}

            # Coefficient multipliers for Agf
            set Fc [$adb parm get aam.FRC.civconcern.$row(civc_g)]
            let Agf {$agf * $Fc * $row(fmult_g) / $frcmultD}

            # NEXT, populate transient input data for computing
            # casualties and time of combat 
            set idata(Afg)   $Afg
            set idata(Agf)   $Agf
            set idata(Rfg)   $Rfg
            set idata(Rgf)   $Rgf
            set idata(DPf)   $row(desig_pers_f)
            set idata(DPg)   $row(desig_pers_g)
            set idata(Tleft) $row(hours_left)

            lassign [$self ComputeCasualties [array get idata]] PRf PRg t

            # NEXT, minumum casualty of 1 for the attacker. If both
            # have an ATTACK ROE, arbitrarily choose f. This prevents
            # force ratios from becoming unchanged if there are two
            # evenly matched, small force groups where one is very close to a 
            # posture change and the minimum fight time is not enough to 
            # change that.
            set casF 0
            set casG 0

            if {$row(roe_f) eq "ATTACK"} {
                let casF {max(1,$row(desig_pers_f) - $PRf)}
                let casG {max(0,$row(desig_pers_g) - $PRg)}
            } else {
                let casG {max(1,$row(desig_pers_g) - $PRg)}
                let casF {max(0,$row(desig_pers_f) - $PRf)}
            }

            # NEXT, store combat outcome data for later
            # adjudication
            lappend outcome $row(n) $row(f) $row(g) $casF $casG $t
        }

        # NEXT adjudicate the outcome of any fighting
        foreach {n f g casF casG t} $outcome {
            $adb eval {
                UPDATE working_force
                SET cas_f        = cas_f+$casF,
                    cas_g        = cas_g+$casG,
                    pers_f       = pers_f-$casF,
                    pers_g       = pers_g-$casG,
                    desig_pers_f = desig_pers_f-$casF,
                    desig_pers_g = desig_pers_g-$casG,
                    hours_left   = max(0.0, hours_left-$t)
                WHERE n=$n AND f=$f AND g=$g            
            }
        }

        # NEXT, indicate more combat possible if fighting occurred
        if {[llength $outcome] > 0} {
            return 1
        }

        # NEXT, combat is done 
        return 0
    }

    # ComputeCasualties tdata
    #
    # tdata   - dictionary of transient data
    #
    # This method takes the contents of the supplied dictionary and
    # computes the number of casualties taken by one or two sides in
    # combat.  It returns, in a list, the number of personnel remaining in
    # the first group, number of personnel remaining in the second group 
    # and the amount of time expended during combat.

    method ComputeCasualties {tdata} {
        dict with tdata {}

        # FIRST, if Afg and Agf are non-zero we need to compute
        # the constants C1 and C2 that will determine the combat time
        if {$Afg > 0.0 && $Agf > 0.0} {
            let rootA {sqrt($Agf*$Afg)}

            # NEXT, combat time constants
            let C1 {0.5 * (($DPf/sqrt($Agf)) - ($DPg/sqrt($Afg)))}
            let C2 {0.5 * (($DPf/sqrt($Agf)) + ($DPg/sqrt($Afg)))}

            # NEXT, handle the case where C1 is 0.0, which means that
            # fighting time should be the time remaining
            if {$C1 == 0.0} {
                set t $Tleft
            } elseif {$C2/$C1 < 0.0} {
                let Larg {
                    $C2/$C1*($Rfg*sqrt($Afg) - sqrt($Agf)) /
                            ($Rfg*sqrt($Afg) + sqrt($Agf))
                }

                let t {0.5/$rootA * log($Larg)}
            } else {
                let Larg {
                    $C2/$C1*(sqrt($Afg) - $Rgf*sqrt($Agf)) /
                            (sqrt($Afg) + $Rgf*sqrt($Agf))

                }

                let t {0.5/$rootA * log($Larg)}
            }

            # NEXT, conbat time cannot exceed time left 
            let t {min($t,$Tleft)}

            # NEXT, personnel remaining, protect against negative personnel
            let PRf {max(0,
                entier(floor($C1*sqrt($Agf)*exp($rootA*$t) +
                             $C2*sqrt($Agf)*exp(-$rootA*$t))))
            }

            let PRg {max(0,
                entier(floor(-1.0*$C1*sqrt($Afg)*exp($rootA*$t) +
                                  $C2*sqrt($Afg)*exp(-$rootA*$t))))
            }        
        } elseif {$Agf > 0.0} {
            # NEXT, Afg is 0.0; only f suffers casualties
            let t {($DPf - $Rfg * $DPg) / ($Agf * $DPg)} 

            # NEXT, enforce the max combat time
            let t {min($t,$Tleft)}

            set PRg $DPg

            let PRf {max(0,entier(floor($DPf - $Agf * $DPg * $t)))}   
        } else {
            # NEXT, Agf is 0.0; only g suffers casualties
            let t {($DPg - $Rgf * $DPf) / ($Afg * $DPf)}

            # NEXT, enforce the max combat time
            let t {min($t,$Tleft)}

            set PRf $DPf

            let PRg {max(0,entier(floor($DPg - $Afg * $DPf * $t)))}
        }

        # NEXT, return personnel remaining for both sides and time expended
        return [list $PRf $PRg $t]
    }

    #-------------------------------------------------------------------
    # Attrition Assessment

    # assess
    #
    # This routine is to be called every tick to do the 
    # attrition assessment.

    method assess {} {
         $adb log normal aam "assess"

        # FIRST, clear out temporary table 
        $adb eval {
            DELETE FROM working_force;
        }

        # NEXT, create SAT and COOP dicts to hold transient data
        set sdict [dict create]
        set cdict [dict create]

        # NEXT, force on force combat and collateral civilian casualties
        if {[$adb parm get aam.maxCombatTimeHours] > 0} {
            $self ComputeEffectiveForce
            $self BuildWorkingForceTable
            $self AllocateForce
            $self DoGroupCombat
        }

        # NEXT, Apply all saved magic attrition. This updates 
        # units and deployments, and accumulates all civilian 
        # attrition as input to the CIVCAS rule set.
        $self ApplyAttrition

        # NEXT, assess the attitude implications of all attrition for
        # this tick.
        $adb ruleset CIVCAS assess $sdict $cdict

        # NEXT, clear the saved data for this tick; we're done.
        set alist ""
        set sdict ""
        set cdict ""
        array unset roedict
    }

    #-------------------------------------------------------------------
    # ROE Tactic API 

    # setroe n f rdict
    #
    # n       - a neighborhood in which g assumes an ROE
    # f       - a force group assuming the ROE
    # rdict   - dictionary of ROE key/values
    #
    # rdict contains the following data related to how g should conduct
    # itself while in combat against other force groups in n:
    #
    #    $g  => dictionary of ROE data for the FRC group f is engaging
    #        -> roe => the ROE $f is attempting with $g: ATTACK or DEFEND
    #        -> athresh => the force/enemy ratio below which $f DEFENDs
    #        -> dthresh => the force/enemy ratio below which $f WITHDRAWs
    #        -> civc => $f's concern for civilian casualties
    #
    # The data in this array of dictionaries is used to set up the initial
    # conditions of the various conflicts between FRC groups by neighborhood.
    # It should be noted that just because a FRC group is ordered to assume
    # a posture via the ROE, that posture may not be attainable due to
    # the computed force ratios.

    method setroe {n f g rdict} {
        dict set roedict($n) $f $g $rdict 
    }

    # hasroe n g f
    #
    # n   - a neighborhood
    # f   - a force group
    # g   - other force group
    #
    # This method returns a flag indicating whether g has an ROE already
    # set against g in n.  This is used during ROE tactic execution to
    # determine whether an ROE has already been set and, therefore, cannot
    # be overridden.

    method hasroe {n f g} {
        if {![info exists roedict($n)]} {
            return 0
        }

        return [dict exists $roedict($n) $f $g]
    }

    # getroe
    #
    # Returns the roedict as a dictionary

    method getroe {} {
        return [array get roedict]
    }

    #-------------------------------------------------------------------
    # Attrition, from ATTRIT tactic
    # TBD: Use this with AAM combat? (mode always GROUP)
    
    # attrit parmdict
    #
    # parmdict
    # 
    # mode          Mode of attrition: GROUP or NBHOOD 
    # casualties    Number of casualties taken by GROUP or NBHOOD
    # n             The neighborhood 
    # f             The group if mode is GROUP
    # g1            Responsible force group, or ""
    # g2            Responsible force group, or ""
    # 
    # Adds a record to the magic attrit table for adjudication at the
    # next aam assessment.
    #
    # g1 and g2 are used only for attrition to a civilian group

    method attrit {parmdict} {
        lappend alist $parmdict
    }

    #-------------------------------------------------------------------
    # DoGroupCombat

    # DoGroupCombat
    #
    # Updates force allocation based on ROEs and computes attrition to
    # force groups and civilian groups.

    method DoGroupCombat {} {
        set moreCombat 1
        while {$moreCombat} {
            $self SetGroupPosture   
            set moreCombat [$self ComputeForceGroupAttrition]
        }

        # NEXT, assess casualties to force groups 
        $adb eval {
            SELECT * FROM working_force
            WHERE cas_f > 0 OR cas_g > 0
        } row {
            set parmdict [dict create]
            dict set parmdict mode GROUP
            dict set parmdict g1 ""
            dict set parmdict g2 ""

            if {$row(cas_f) > 0} {
                dict set parmdict casualties $row(cas_f)
                dict set parmdict n $row(n)
                dict set parmdict f $row(f)
                $self attrit $parmdict
            }

            if {$row(cas_g) > 0} {
                dict set parmdict casualties $row(cas_g)
                dict set parmdict n $row(n)
                dict set parmdict f $row(g)
                $self attrit $parmdict                
            }
        }
    }

    #-------------------------------------------------------------------
    # Apply Attrition
    
    # ApplyAttrition
    #
    # Applies the attrition from magic attrition and then that
    # accumulated by the normal attrition algorithms.

    method ApplyAttrition {} {
        # FIRST, apply the magic attrition
        foreach adict $alist {
            dict with adict {}
            switch -exact -- $mode {
                NBHOOD {
                    $self AttritNbhood $n $casualties $g1 $g2
                }

                GROUP {
                    $self AttritGroup $n $f $casualties $g1 $g2
                }

                default {error "Unrecognized attrition mode: \"$mode\""}
            }
        }

    }

    # AttritGroup n f casualties g1 g2
    #
    # parmdict      Dictionary of order parms
    #
    #   n           Neighborhood in which attrition occurs
    #   f           Group taking attrition.
    #   casualties  Number of casualties taken by the group.
    #   g1          Responsible force group, or ""
    #   g2          Responsible force group, or "".
    #
    # Attrits the specified group in the specified neighborhood
    # by the specified number of casualties (all of which are kills).
    #
    # The group's units are attrited in proportion to their size.
    # For FRC/ORG groups, their deployments in deploy_tng are
    # attrited as well, to support deployment without reinforcement.
    #
    # g1 and g2 are used only for attrition to a civilian group.

    method AttritGroup {n f casualties g1 g2} {
         $adb log normal aam "AttritGroup $n $f $casualties $g1 $g2"

        # FIRST, determine the set of units to attrit.
        $adb eval {
            UPDATE units
            SET attrit_flag = 0;

            UPDATE units
            SET attrit_flag = 1
            WHERE n=$n 
            AND   g=$f
            AND   personnel > 0
        }

        # NEXT, attrit the units
        $self AttritUnits $casualties $g1 $g2

        # NEXT, attrit FRC/ORG deployments.
        if {[$adb group gtype $f] in {FRC ORG}} {
            $self AttritDeployments $n $f $casualties
        }
    }

    # AttritNbhood n casualties g1 g2
    #
    # parmdict      Dictionary of order parms
    #
    #   n           Neighborhood in which attrition occurs
    #   casualties  Number of casualties taken by the group.
    #   g1          Responsible force group, or "".
    #   g2          Responsible force group, or "".
    #
    # Attrits all civilian units in the specified neighborhood
    # by the specified number of casualties (all of which are kills).
    # Units are attrited in proportion to their size.

    method AttritNbhood {n casualties g1 g2} {
         $adb log normal aam "AttritNbhood $n $casualties $g1 $g2"

        # FIRST, determine the set of units to attrit (all
        # the CIV units in the neighborhood).
        $adb eval {
            UPDATE units
            SET attrit_flag = 0;

            UPDATE units
            SET attrit_flag = 1
            WHERE n=$n 
            AND   gtype='CIV'
            AND   personnel > 0
        }

        # NEXT, attrit the units
        $self AttritUnits $casualties $g1 $g2
    }

    # AttritUnits casualties g1 g2
    #
    # casualties  Number of casualties taken by the group.
    # g1          Responsible force group, or "".
    # g2          Responsible force group, or "".
    #
    # Attrits the units marked with the attrition flag 
    # proportional to their size until
    # all casualites are inflicted or the units have no personnel.
    # The actual work is performed by AttritUnit.

    method AttritUnits {casualties g1 g2} {
        # FIRST, determine the number of personnel in the attrited units
        set total [$adb eval {
            SELECT total(personnel) FROM units
            WHERE attrit_flag
        }]

        # NEXT, compute the actual number of casualties.
        let actual {min($casualties, $total)}

        if {$actual == 0} {
             $adb log normal aam \
                "Overkill; no casualties can be inflicted."
            return 
        } elseif {$actual < $casualties} {
             $adb log normal aam \
                "Overkill; only $actual casualties can be inflicted."
        }
        
        # NEXT, apply attrition to the units, in order of size.
        set remaining $actual

        $adb eval {
            SELECT u                                   AS u,
                   g                                   AS g,
                   gtype                               AS gtype,
                   personnel                           AS personnel,
                   n                                   AS n,
                   $actual*(CAST (personnel AS REAL)/$total) 
                                                       AS share
            FROM units
            WHERE attrit_flag
            ORDER BY share DESC
        } row {
            # FIRST, allocate the share to this body of people.
            let kills     {entier(min($remaining, ceil($row(share))))}
            let remaining {$remaining - $kills}

            # NEXT, compute the attrition.
            let take {entier(min($row(personnel), $kills))}

            # NEXT, attrit the unit
            set row(g1)         $g1
            set row(g2)         $g2
            set row(casualties) $take

            $self AttritUnit [array get row]

            # NEXT, we might have finished early
            if {$remaining == 0} {
                break
            }
        }
    }

    # AttritUnit parmdict
    #
    # parmdict      Dictionary of unit data, plus g1 and g2
    #
    # Attrits the specified unit by the specified number of 
    # casualties (all of which are kills); also decrements
    # the unit's staffing pool.  This is the fundamental attrition
    # routine; the others all flow down to this.
 
    method AttritUnit {parmdict} {
        dict with parmdict {}

        # FIRST, log the attrition
        let personnel {$personnel - $casualties}

         $adb log normal aam \
          "Unit $u takes $casualties casualties, leaving $personnel personnel"
            
        # NEXT, update the unit.
        $adb unit personnel $u $personnel

        # NEXT, if this is a CIV unit, attrit the unit's
        # group.
        if {$gtype eq "CIV"} {
            # FIRST, attrit the group 
            $adb demog attrit $g $casualties

            # NEXT, save the attrition for attitude assessment
            $self SaveCivAttrition $parmdict
        } else {
            # FIRST, It's a force or org unit.  Attrit its pool in
            # its neighborhood.
            $adb personnel attrit $n $g $casualties
        }

        return
    }

    # AttritDeployments n g casualties
    #
    # n           The neighborhood in which the attrition took place.
    # g           The FRC or ORG group that was attrited.
    # casualties  Number of casualties taken by the group.
    #
    # Attrits the deployment of the given group in the given neighborhood, 
    # spreading the attrition across all DEPLOY tactics active during
    # the current tick.
    #
    # This is to support DEPLOY without reinforcement.  The deploy_tng
    # table lists the actual troops deployed during the last
    # tick by each DEPLOY tactic, broken down by neighborhood and group.
    # This routine removes casualties from this table, so that the 
    # attrited troop levels can inform the next round of deployments.

    method AttritDeployments {n g casualties} {
        # FIRST, determine the number of personnel in the attrited units
        set total [$adb eval {
            SELECT total(personnel) FROM deploy_tng
            WHERE n=$n AND g=$g
        }]

        # NEXT, compute the actual number of casualties.
        let actual {min($casualties, $total)}

        if {$actual == 0} {
            return 
        }

        # NEXT, apply attrition to the tactics, in order of size.
        set remaining $actual

        foreach {tactic_id personnel share} [$adb eval {
            SELECT tactic_id,
                   personnel,
                   $actual*(CAST (personnel AS REAL)/$total) AS share
            FROM deploy_tng
            WHERE n=$n AND g=$g
            ORDER BY share DESC
        }] {
            # FIRST, allocate the share to this body of troops.
            let kills     {entier(min($remaining, ceil($share)))}
            let remaining {$remaining - $kills}

            # NEXT, compute the attrition.
            let take {entier(min($personnel, $kills))}

            # NEXT, attrit the tactic's deployment.
            $adb eval {
                UPDATE deploy_tng
                SET personnel = personnel - $take
                WHERE tactic_id = $tactic_id AND n = $n AND g = $g
            }

            # NEXT, we might have finished early
            if {$remaining == 0} {
                break
            }
        }
    }
    
    # SaveCivAttrition parmdict
    #
    # parmdict contains the following keys/data:
    #
    # n           The neighborhood in which the attrition took place.
    # g           The CIV group receiving the attrition
    # casualties  The number of casualties
    # g1          A responsible force group, or ""
    # g2          A responsible force group, g2 != g1, or ""
    #
    # Accumulates the attrition for later attitude assessment.

    method SaveCivAttrition {parmdict} {
        dict with parmdict {}

        # FIRST, accumulate by CIV group for SAT effects
        if {![dict exists $sdict $g]} {
            dict set sdict $g 0
        }

        let sum {[dict get $sdict $g] + $casualties}
        dict set sdict $g $sum

        # NEXT, accumulate by CIV and FRC group for COOP effects
        if {$g1 ne ""} {
            if {![dict exists cdict "$g $g1"]} {
                dict set cdict "$g $g1" 0
            }

            let sum {[dict get $cdict "$g $g1"] + $casualties}
            dict set cdict "$g $g1" $sum
        }

        if {$g2 ne ""} {
            if {![dict exists cdict "$g $g2"]} {
                dict set cdict "$g $g2" 0
            }

            let sum {[dict get $cdict "$g $g2"] + $casualties}
            dict set cdict "$g $g2" $sum
        }

        return 
    }

    #-------------------------------------------------------------------
    # Tactic Order Helpers

    # AllButG1 g1
    #
    # g1 - A force group
    #
    # Returns a list of all force groups but g1 and puts "NONE" at the
    # beginning of the list.
    #
    # TBD: Should go in tactic_attrit.tcl

    method AllButG1 {g1} {
        set groups [ptype frcg+none names]
        ldelete groups $g1

        return $groups
    }
}



