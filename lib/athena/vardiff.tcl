#-----------------------------------------------------------------------
# TITLE:
#   vardiff.tcl
#
# AUTHOR:
#   Will Duquette
#
# DESCRIPTION:
#   Variable difference base class
#
#-----------------------------------------------------------------------

oo::class create ::athena::vardiff {
    meta type *          ;# Type is undefined; subclasses should override.
    meta category "???"  ;# PMESII category is undefined; subclasses should
                          # override.

    variable comp     ;# comparison object
    variable keydict  ;# Key dictionary
    variable val1     ;# Value from case 1
    variable val2     ;# Value from case 2
    variable gotdiffs ;# 1 if we've computed diffs, and 0 otherwise.
    variable diffs    ;# List of vardiffs of significant inputs.

    # constructor comp_ keydict_ val1_ val2_
    #
    # comp_     - The comparison(n) object that owns this difference.
    # keydict_  - A dictionary of variable keys and values.
    # val1_     - The value of the variable for the first scenario/time
    #             pair
    # val2_     - The value of the variable for the second scenario/time
    #             pair.
    #
    # Saves the inputs into instance variables.

    constructor {comp_ keydict_ val1_ val2_} {
        set comp     $comp_
        set keydict  $keydict_
        set val1     $val1_
        set val2     $val2_
        set gotdiffs 0
        set diffs    [list]
    }

    # name
    #
    # Computes the variable name from the variable type and the 
    # key dictionary.

    method name {} {
        set prefix [lindex [split [my type] .] 0]

        dict for {key val} $keydict {
            append prefix /$val
        }
        return $prefix
    }

    # keydict
    #
    # Returns the dictionary of key names and values.

    method keydict {} {
        return $keydict
    }

    # keys
    #
    # Returns the names of the keys in the keydict, 
    # e.g., {g c} for a satisfaction level

    method keys {} {
        return [dict keys $keydict]
    }

    # key name
    #
    # Returns the value of the named key, e.g., "AUT" for key "c".

    method key {name} {
        return [dict get $keydict $name]
    }

    # val1
    #
    # Returns the raw value of the variable for the first scenario/time 
    # pair.

    method val1 {} {
        return $val1
    }

    # val2
    #
    # Returns the raw value of the variable for the second scenario/time 
    # pair.

    method val2 {} {
        return $val2
    }

    # fmt1
    #
    # Returns the formatted value of the variable for the first 
    # scenario/time pair.

    method fmt1 {} {
        return [my format $val1]
    }

    # fmt2
    #
    # Returns the formatted value of the variable for the second 
    # scenario/time pair.

    method fmt2 {} {
        return [my format $val2]
    }

    # format val
    #
    # val   - A value of the variable's type
    #
    # Returns the formatted value.  This can be overridden by
    # subclasses; it is intended to return a minimal formatted
    # value for display.  Override in subclasses

    method format {val} {
        return $val
    }

    # fancy1
    #
    # Returns the fancy value of the variable for the first 
    # scenario/time pair, i.e., formatted with elaborations 
    # (symbolic value, units, etc.).

    method fancy1 {} {
        return [my fancy $val1]
    }

    # fancy2
    #
    # Returns the fancy value of the variable for the second 
    # scenario/time pair, i.e., formatted with elaborations 
    # (symbolic value, units, etc.).

    method fancy2 {} {
        return [my fancy $val2]
    }

    # fancy val
    #
    # val   - A value of the variable's type
    #
    # Returns the formatted value with elaborations, e.g.,
    # including a symbolic value, units, etc.  Defaults to the
    # 'format'.  Override in subclasses as needed.

    method fancy {val} {
        return [my format $val]
    }

    # context
    #
    # Any additional info that might be useful to the analyst.
    # Override in subclasses as needed.

    method context {} {
        return ""
    }

    # score
    #
    # A ranking score.  By default, it's the delta of the
    # two values, which are assumed to be numeric.  
    #
    # Subclasses should override this if necessary.

    method score {} {
        my delta
    }

    # delta
    #
    # The absolute difference of the two values, only if that makes
    # sense.  Subclasses should override this if necessary.

    method delta {} {
        expr {abs([my val1] - [my val2])}
    }

    # different
    #
    # Returns 1 if val1 isn't "eq" val2, and 0 otherwise.

    method different {} {
        expr {$val1 ne $val2}
    }

    # significant
    #
    # Returns 1 if val1 is significantly different than val2, and 0
    # otherwise.  If the vartype's "active" flag is false, then 
    # returns 0.
    
    method significant {} {
        if {[athena::compdb get [my type].active]} {
            return [my IsSignificant]
        } else {
            return 0
        }
    }

    # IsSignificant
    #
    # Subclasses override this to define their own significance tests.
    # By default, a difference is significant if the two values are
    # not identical.

    method IsSignificant {} {
        my different
    }

    # view
    #
    # Returns a view on the difference record.

    method view {} {
        dict set result type     [my type]
        dict set result name     [my name]
        dict set result category [my category]

        dict for {key value} $keydict {
            dict set result $key $value
        }
        
        dict set result val1      $val1
        dict set result fmt1      [my fmt1]
        dict set result fancy1    [my fancy1]
        dict set result val2      $val2
        dict set result fmt2      [my fmt2]
        dict set result fancy2    [my fancy2]
        dict set result score     [my score]
        dict set result delta     [expr {
            [my delta] ne "" ? [my format [my delta]] : ""
        }]
        dict set result narrative [my narrative]
        dict set result context   [my context]

        return $result
    }

    # inputs
    #
    # Returns a list of the names of the significant inputs for
    # this vardiff, or the empty list if !gotdiffs.

    method inputs {} {
        set result [list]

        if {[my gotdiffs]} {
            foreach diff [my diffs] {
                lappend result [$diff name]
            }
        }


        return $result
    }


    # huddle
    #
    # Returns a huddle object corresponding to this vardiff.  It 
    # contains the view plus the inputs.

    method huddle {} {
        set hvar [huddle compile dict [my view]]
        huddle set hvar inputs [huddle compile list [my inputs]]
        return $hvar
    }


    # gotdiffs
    #
    # Returns 1 if we've found diffs for this vardiff, and 0 otherwise.

    method gotdiffs {} {
        return $gotdiffs
    }

    # diffs
    #
    # Computes vardiffs for significant differences in variable
    # inputs, adding them to the comparison object, and returns
    # a list of them.

    method diffs {} {
        if {!$gotdiffs} {
            my FindDiffs
            set gotdiffs 1
        }

        return $diffs
    }

    # FindDiffs
    #
    # Subclasses should override this if drilling down is possible.

    method FindDiffs {} {
        return
    }


    # diffadd vartype val1 val2 keys...
    #
    # vartype  - A vardiff type.
    # val1     - The value from s1/t1
    # val2     - The value from s2/t2
    # keys...  - Key values for the vardiff class
    #
    # Given a vardiff type and a pair of values, saves a significant output
    # diff if the difference between the two values is significant.  
    #
    # Returns the diff if it was significant, and "" otherwise. 

    method diffadd {vartype val1 val2 args} {
        set diff [$comp add $vartype $val1 $val2 {*}$args]

        if {$diff ne ""} {
            ladd diffs $diff
        }
    }

    #-------------------------------------------------------------------
    # Narrative Tools

    # narrative
    #
    # Returns a narrative string for the vardiff.  This should be
    # overridden by subclasses.

    method narrative {} {
        return [my DeltaNarrative]
    }

    method DeltaNarrative {{title "Value"} {units ""}} {
        set text "$title "

        if {[my val2] > [my val1]} {
            append text "increased"
        } else {
            append text "decreased"
        }

        append text " by [my format [my delta]]"

        if {$units ne ""} {
            append text " $units"
        }

        append text "."

        return $text
    }

}
