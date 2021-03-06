#-----------------------------------------------------------------------
# TITLE:
#    ruleset_manager.tcl
#
# AUTHOR:
#    Will Duquette
#
# DESCRIPTION:
#    athena(n): Rule Set manager
#
#    This module is responsible for creating rule set objects and 
#    passing events and situations to them for assessment.
#
#-----------------------------------------------------------------------

snit::type ::athena::ruleset_manager {
    # Initial driver ID.  This is set to 1000 so as to be higher than
    # a standard cause's numeric ID, so that numeric driver IDs can be 
    # used as numeric cause IDs.  There are fewer than 100 standard causes;
    # using 1000 leaves lots of room and is visually distinctive when
    # looking at the database.

    typevariable initialID 1000

    
    #-------------------------------------------------------------------
    # Components

    component adb ;# The athenadb(n) instance

    #-------------------------------------------------------------------
    # Instance Variables

    # Rule set object cache: rule set objects by rule set name.
    variable cache -array {}
    
    #-------------------------------------------------------------------
    # Constructor

    # constructor adb_
    #
    # adb_    - The athenadb(n) that owns this instance.
    #
    # Initializes instances of the type.

    constructor {adb_} {
        set adb $adb_
    }

    #-------------------------------------------------------------------
    # Public Methods
    #
    # These routines query information about the entities; they are
    # not allowed to modify them.

    # If the  method name is a rule set name, the remainder of the
    # command is passed directly to the ruleset object.
    delegate method * using {%s call %m}


    # names
    #
    # Returns the list of rule set names

    method names {} {
        return [::athena::ruleset names]
    }

    # call setname args
    #
    # setname   - A rule set name
    # args      - Arguments to pass to it.
    #
    # Calls the ruleset given the arguments, creating the rule set if 
    # need be.

    method call {setname args} {
        # FIRST, get the rule set
        set rs [$self GetRuleSet $setname]

        # NEXT, Pass the command to the rule set.
        $rs {*}$args
    }

    # GetRuleSet setname
    #
    # setname  - A rule set name
    #
    # Returns the ruleset object, creating it if necessary.

    method GetRuleSet {setname} {
        if {[info exists cache($setname)]} {
            return $cache($setname)
        }

        require {$setname in [$self names]} "Unknown ruleset: \"$setname\""

        set cache($setname) \
            [::athena::ruleset_$setname create ${selfns}::$setname $adb]
    }

    # get setname signature
    #
    # setname    - A driver type/ruleset name
    # signature  - A driver signature
    #
    # Returns the driver_id for the driver type and signature, if one
    # exists, and "" otherwise.

    method get {setname signature} {
        return [$adb onecolumn {
            SELECT driver_id FROM drivers
            WHERE dtype=$setname AND signature=$signature
        }]
    }

    # getid setname fdict
    #
    # setname  - A driver type/ruleset name
    # fdict    - A firing dictionary for the ruleset
    #
    # Assigns a new driver ID for the ruleset.

    method getid {setname fdict} {
        # FIRST, get the rule set and the signature.
        set rs [$self GetRuleSet $setname]
        set signature [$rs signature $fdict]

        # NEXT, if there's a driver with that signature return it.
        set id [$self get $setname $signature]

        if {$id ne ""} {
            return $id
        }

        # NEXT, this is a new get a new driver ID
        $adb eval {
            SELECT coalesce(max(driver_id)+1, $initialID) 
            AS new_id FROM drivers
        } {}

        # NEXT, create the entry
        $adb eval {
            INSERT INTO drivers(driver_id, dtype, signature)
            VALUES($new_id, $setname, $signature);
        }

        return $new_id
    }


    # qid setname signature
    #
    # Returns the driver's QID.

    method qid {setname signature} {
        return "driver/$setname/[join $signature /]"
    }

    # id2qid id
    #
    # id   - A Driver ID
    #
    # Given the driver ID, return the qualified entity ID.
    # Returns "" if there is no such driver.

    method id2qid {id} {
        $adb eval {
            SELECT setname, signature
            FROM drivers
            WHERE driver_id = $id
        } {
            return [$self qid $setname $signature]
        }

        return ""
    }

    # qid2id qid
    #
    # qid   - A Driver QID
    #
    # Given the driver QID, return the numeric ID.
    # Returns "" if there is no such driver.

    method qid2id {qid} {
        set tokens [split [string toupper $qid] /]
        set setname [lindex $tokens 1]
        set signature [lrange $tokens 2 end]

        return [$self get $setname $signature]
    }

    # rulename rule
    #
    # rule - A ruleset rule, e.g., CIVCAS-1-1
    #
    # Returns the full rule name
    method rulename {rule} {
        set setname [lindex [split $rule -] 0]
        return [::athena::ruleset_${setname} rulename $rule]
    }

    # narrative setname fdict
    #
    # setname - A rule set name
    # fdict   - A firing dictionary
    #
    # Returns the firing narrative.

    method narrative {setname fdict} {
        return [$self call $setname narrative $fdict]
    }

    # detail setname fdict ht
    #
    # setname - A rule set name
    # fdict   - A firing dictionary
    # ht      - An htools handle
    #
    # Returns the firing detail.

    method detail {setname fdict ht} {
        return [$self call $setname detail $fdict $ht]
    }
}





