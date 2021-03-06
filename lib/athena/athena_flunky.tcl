#-----------------------------------------------------------------------
# TITLE:
#    athena_flunky.tcl
#
# PROJECT:
#   athena - Athena Regional Stability Simulation
#
# AUTHOR:
#    Will Duquette
#
# DESCRIPTION:
#    athena(n): Athena Order Flunky Adaptor
#
#    This class subclasses and adapts ::marsutil::order_flunky, providing
#    additional features for use by Athena (e.g., RDB transactions and
#    monitoring)
#
#-----------------------------------------------------------------------

#-----------------------------------------------------------------------
# Athena Order Flunky Adaptor

oo::class create ::athena::athena_flunky {
    superclass ::marsutil::order_flunky

    #-------------------------------------------------------------------
    # Instance Variables

    # adb - The athenadb(n) handle

    variable adb

    # transMode - if "transaction", orders are executed within an RDB 
    # transaction; if "script", they are not.  The default is 
    # "transaction".

    variable transMode

    # monitorFlag - if 1, we do RDB monitoring on order execution, undo,
    # and redo, and if 0 we don't.

    variable monitorFlag

    #-------------------------------------------------------------------
    # Constructor

    # constructor adb_
    #
    # adb_   - The athenadb(n) instance of which this is a component.

    constructor {adb_} {
        next ::athena::orders

        set adb         $adb_
        set transMode   transaction
        set monitorFlag 1
    }
    
    
    #-------------------------------------------------------------------
    # Configuration

    # monitor ?flag?
    #
    # flag - on, off, or any boolean.
    #
    # Sets and returns the monitor flag.

    method monitor {{flag ""}} {
        if {$flag ne ""} {
            set monitorFlag $flag
        }

        return [expr {$monitorFlag ? 1 : 0}]
    }

    # transactions ?flag?
    #
    # flag - on, off, or any boolean
    #
    # Returns the transactions flag.  If a flag is given, assigns it.

    method transactions {{flag ""}} {
        if {$flag ne ""} {
            set transMode [expr {$flag ? "transaction" : "script"}]
        }

        return [expr {$transMode eq "transaction"}]
    }
    

    #-------------------------------------------------------------------
    # order_flunky(n) tweaks

    # state ?newState?
    #
    # newState - A new simulation state, e.g., PAUSED.
    #
    # Sets/queries the simulation state.

    method state {{newState ""}} {
        set result [next $newState]
        $adb notify order <Sync>

        return $result
    }    

    # make name args
    #
    # Ensures that the order is created with the athenadb instance.

    method make {name args} {
        next $name $adb {*}$args
    }

    # check name ?parm value...?
    #
    # name - An order name
    # args - A dictionary of order parameters and values
    #
    # Validates the order parameters without executing it.
    # Returns "" on success, and throws REJECT on error.

    method check {name args} {
        set o [my make $name]

        set parmdict [dict create]
        foreach {parm value} $args {
            if {$parm in [$o parms]} {
                dict set parmdict $parm $value
            }
        }

        $o setdict $parmdict

        try {
            if {[$o valid]} {
                return ""
            }

            throw REJECT [$o errdict]
        } finally {
            $o destroy
        }
    }

    # execute mode order
    #
    # Wraps the order_flunky "execute" method.  Adds RDB transactions
    # and monitoring (unless the order isn't monitored).

    method execute {mode order} {
        if {[$order monitor] && $monitorFlag} {
            $adb monitor $transMode {
                set result [next $mode $order]
            }
        } else {
            set result [next $mode $order]
        }

        return $result
    }

    # _onExecute order
    #
    # Adds the order to the CIF

    method _onExecute {order} {
        my AddToCIF $order
    }

    # undo
    #
    # Wraps the order_flunky "undo" method.  Adds RDB transactions
    # and monitoring.

    method undo {} {
        if {$monitorFlag} {
            $adb monitor $transMode {
                next
            }
        } else {
            next
        }

        return
    }


    # _onUndo order
    #
    # Removes the top order from the CIF

    method _onUndo {order} {
        set maxid [$adb onecolumn {
            SELECT max(id) FROM cif
        }]


        $adb eval {
            DELETE FROM cif
            WHERE id = $maxid
        }
        $adb log normal flunky "Undo: [$order name] [$order getdict]"
        $adb notify order <Sync>
    }


    # redo
    #
    # Wraps the order_flunky "redo" method.  Adds RDB transactions
    # and monitoring.

    method redo {} {
        if {$monitorFlag} {
            $adb monitor $transMode {
                next
            }
        } else {
            next
        }

        return
    }

    # _onRedo order
    #
    # Adds the order to the CIF

    method _onRedo {order} {
        my AddToCIF $order
    }

    # AddToCIF order
    #
    # Adds the order to the CIF.

    method AddToCIF {order} {
        set now [$adb clock now]

        set name      [$order name]
        set narrative [$order narrative]
        set parmdict  [$order getdict]

        $adb eval {
            INSERT INTO cif(time,name,narrative,parmdict)
            VALUES($now, $name, $narrative, $parmdict);
        }

        $adb log normal flunky "Order: $name $parmdict"
        $adb notify order <Sync>
    }
}


