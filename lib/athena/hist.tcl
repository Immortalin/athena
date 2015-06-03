#-----------------------------------------------------------------------
# TITLE: 
#    hist.tcl
#
# AUTHOR:
#    Will Duquette
#
# DESCRIPTION:
#   athena(n): Results history manager
#
# History is saved for t=0 on lock and for t > 0 at the end of each
# time-step's activities.  [hist tick] saves all history that is
# saved at every tick; [hist econ] saves all history that is saved
# at each econ tock.
#
#-----------------------------------------------------------------------

snit::type ::athena::hist {
    #-------------------------------------------------------------------
    # Type variables

    # histVars
    #
    # Array of history variables and their keys. These correspond to the 
    # hist_* tables.

    typevariable histVars -array {
        aam_battle   {n f g}
        activity_nga {n g a}
        control      {n}
        coop         {f g}
        deploy_ng    {n g}
        econ         {}
        flow         {f g}
        hrel         {f g}
        mood         {g}
        nbmood       {n}
        nbur         {n}
        npop         {n}
        plant_a      {a}
        plant_n      {n}
        plant_na     {n a}
        pop          {g}
        sat          {g c}
        security     {n g}
        service_sg   {s g}
        support      {n a}
        volatility   {n}
        vrel         {g a}
    }

    #-------------------------------------------------------------------
    # Components

    component adb  ;# The athenadb(n) instance

    #-------------------------------------------------------------------
    # Construcutor

    # constructor adb_
    #
    # adb_    - The athenadb(n) that owns this instance.
    #
    # Initializes instances of this type.

    constructor {adb_} {
        set adb $adb_
    }

    #-------------------------------------------------------------------
    # Public Methods

    # purge t
    #
    # t   - The sim time in ticks at which to purge
    #
    # Removes "future history" from the history tables when going
    # backwards in time.  We are paused at time t; all time t 
    # history is behind us.  So purge everything later.
    #
    # On unlock, this will be used to purge all history, including
    # time 0 history, by setting t to -1. NOTE: in the case of t = -1
    # its *much* quicker to leave out the WHERE clause

    method purge {t} {
        if {$t == -1} {
            $adb eval {
                DELETE FROM hist_nbhood;
                DELETE FROM hist_nbgroup;
                DELETE FROM hist_civg;
                DELETE FROM hist_sat_raw;
                DELETE FROM hist_coop;
                DELETE FROM hist_nbcoop;
                DELETE FROM hist_econ;
                DELETE FROM hist_econ_i;
                DELETE FROM hist_econ_ij;
                DELETE FROM hist_plant_na;
                DELETE FROM hist_service_sg;
                DELETE FROM hist_support;
                DELETE FROM hist_hrel;
                DELETE FROM hist_vrel;
                DELETE FROM hist_flow;
                DELETE FROM hist_activity_nga;
                DELETE FROM hist_aam_battle;
            }
        } else {
            $adb eval {
                DELETE FROM hist_nbhood       WHERE t > $t;
                DELETE FROM hist_nbgroup      WHERE t > $t;
                DELETE FROM hist_civg         WHERE t > $t;
                DELETE FROM hist_sat_raw      WHERE t > $t;
                DELETE FROM hist_coop         WHERE t > $t;
                DELETE FROM hist_nbcoop       WHERE t > $t;
                DELETE FROM hist_econ         WHERE t > $t;
                DELETE FROM hist_econ_i       WHERE t > $t;
                DELETE FROM hist_econ_ij      WHERE t > $t;
                DELETE FROM hist_plant_na     WHERE t > $t;
                DELETE FROM hist_service_sg   WHERE t > $t;
                DELETE FROM hist_support      WHERE t > $t;
                DELETE FROM hist_hrel         WHERE t > $t;
                DELETE FROM hist_vrel         WHERE t > $t;
                DELETE FROM hist_flow         WHERE t > $t;
                DELETE FROM hist_activity_nga WHERE t > $t;
                DELETE FROM hist_aam_battle   WHERE t > $t;
            }
        }
    }

    # tick
    #
    # This method is called at each time tick, and preserves data values
    # that change tick-by-tick.  
    #
    # "Significant" outputs (i.e., those used in practice by analysts)
    # are always saved, as are outputs required to construct causal
    # chains.  Other outputs may be disabled by setting the appropriate
    # parameter.

    method tick {} {
        set t [$adb clock now]

        # Attitudes history 
        # SAT
        if {[$adb parm get hist.sat]} {
            $adb eval {
                INSERT INTO hist_sat_raw(t,g,c,sat,base,nat)
                SELECT $t AS t, g, c, sat, bvalue, cvalue 
                FROM uram_sat;
            }
        }

        # COOP
        if {[$adb parm get hist.coop]} {
            $adb eval {
                INSERT INTO hist_coop(t,f,g,coop,base,nat)
                SELECT $t AS t, f, g, coop, bvalue, cvalue
                FROM uram_coop;
            }
        }

        # HREL
        if {[$adb parm get hist.hrel]} {
            $adb eval {
                INSERT INTO hist_hrel(t,f,g,hrel,base,nat)
                SELECT $t AS t, f, g, hrel, bvalue, cvalue
                FROM uram_hrel;
            }
        }

        # VREL 
        if {[$adb parm get hist.vrel]} {
            $adb eval {
                INSERT INTO hist_vrel(t,g,a,vrel,base,nat)
                SELECT $t AS t, g, a, vrel, bvalue, cvalue
                FROM uram_vrel;
            }
        }

        # Neighborhood COOP by FRC group
        if {[$adb parm get hist.nbcoop]} {
            $adb eval {
                INSERT INTO hist_nbcoop(t,n,g,nbcoop)
                SELECT $t AS t, n, g, nbcoop
                FROM uram_nbcoop;
            }
        }

        # Neighborhood history
        $adb eval {
            INSERT INTO hist_nbhood(t,n,a,nbmood,volatility,nbpop,
                                    ur,nbsecurity)
            SELECT $t AS t, n, 
                   C.controller AS a, 
                   U.nbmood, 
                   F.volatility, 
                   D.population,
                   D.ur,
                   F.security
            FROM uram_n    AS U
            JOIN force_n   AS F USING (n)
            JOIN demog_n   AS D USING (n)
            JOIN control_n AS C USING (n);
        }

        # Neighborhood group history
        $adb eval {
            INSERT INTO hist_nbgroup(t,n,g,security,personnel,unassigned)
            SELECT $t AS t, n, g,
                   F.security,
                   F.personnel,
                   coalesce(D.unassigned,0)
            FROM            force_ng   AS F
            LEFT OUTER JOIN deploy_ng  AS D USING (n,g)
        }

        # CIV group history
        $adb eval {
            INSERT INTO hist_civg(t,g,mood,population)
            SELECT $t AS t, g, 
                   U.mood,
                   D.population
            FROM uram_mood AS U
            JOIN demog_g   AS D USING (g);
        }

        if {[$adb parm get hist.plant] && [$adb econ state] eq "ENABLED"} {
            set gpp [money validate [$adb parm get plant.bktsPerYear.goods]]

            $adb eval {
                INSERT INTO hist_plant_na(t,n,a,num,cap)
                SELECT $t AS t, n, a, num, $gpp*num*rho AS cap
                FROM plants_na;
            }
        }

        if {[$adb parm get hist.support]} {
            $adb eval {
                INSERT INTO hist_support(t,n,a,direct_support,support,influence)
                SELECT now(), n, a, direct_support, support, influence
                FROM influence_na;
            }
        }

        if {[$adb parm get hist.service]} {
            $adb eval {
                INSERT INTO hist_service_sg(t,s,g,saturation_funding,required,
                                           funding,actual,expected,expectf,
                                           needs)
                SELECT now(), s, g, saturation_funding, required,
                       funding, actual, expected, expectf, needs
                FROM service_sg
            }
        }

        if {[$adb parm get hist.activity]} {
            $adb eval {
                INSERT INTO hist_activity_nga(t,n,g,a,security_flag,can_do,
                                              nominal,effective,coverage)
                SELECT now(), n, g, a, security_flag, can_do, nominal,
                       effective, coverage
                FROM activity_nga WHERE nominal > 0
            }            
        }
    }

    # Type Method: econ
    #
    # This method is called at each econ tock, and preserves data
    # values that change tock-by-tock.

    method econ {} {
        # FIRST, if the econ model has been disabled we're done.
        if {[$adb econ state] eq "DISABLED"} {
            return
        }

        # NEXT, get the data and save it.
        array set inputs  [$adb econ get In  -bare]
        array set outputs [$adb econ get Out -bare]

        $adb eval {
            -- hist_econ
            INSERT INTO hist_econ(t, consumers, subsisters, labor, 
                                  lsf, csf, rem, cpi, agdp, dgdp, ur)
            VALUES(now(), 
                   $inputs(Consumers), $inputs(Subsisters), $inputs(LF),
                   $inputs(LSF), $inputs(CSF), $inputs(REM),
                   $outputs(CPI), $outputs(AGDP), $outputs(DGDP), 
                   $outputs(UR));
        }

        foreach i {goods pop black actors region world} {
            if {$i in {goods pop black}} {
                $adb eval "
                    -- hist_econ_i
                    INSERT INTO hist_econ_i(t, i, p, qs, rev)
                    VALUES(now(), upper(\$i), \$outputs(P.$i), 
                           \$outputs(QS.$i),\$outputs(REV.$i));
                "
            }

            foreach j {goods pop black actors region world} {
                $adb eval "
                    -- hist_econ_ij
                    INSERT INTO hist_econ_ij(t, i, j, x, qd)
                    VALUES(now(), upper(\$i), upper(\$j), 
                           \$outputs(X.$i.$j), \$outputs(QD.$i.$j)); 
                "
            }
        }
    }

    # vars
    #
    # Returns available history variables and their keys

    method vars {} {
        return [array get histVars]
    }
}
