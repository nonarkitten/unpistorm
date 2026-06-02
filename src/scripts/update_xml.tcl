#
# update_xml.tcl
#
# convert the <config>.xml to <config>_xml.hex
#

package require zlib
puts "MiSTle XML Tool, board = $board, config = $config"

# Function to read the entire file content
proc readFile {filename} {
    # Check if file exists and is readable
    if {![file exists $filename]} {
        error "File '$filename' does not exist."
    }
    if {![file readable $filename]} {
        error "File '$filename' is not readable."
    }

    set fh ""
    set data ""
    # Open file in read mode
    if {[catch {open $filename r} fh]} {
        error "Failed to open file '$filename': $fh"
    }

    # Read the file content
    if {[catch {read $fh} data]} {
        close $fh
        error "Error reading file '$filename': $data"
    }

    # Close the file
    close $fh

    return $data
}

# hexdump for debugging
proc hexdump {string} {
    set where 0
    while {$where<[string length $string]} {
        set str [string range $string $where [expr $where+15]]
        if {![binary scan $str H* t] || $t==""} break
        regsub -all (..) $t {\1 } t2
        set asc ""
        foreach i $t2 {
            scan $i %2x c
            append asc [expr {$c>=32 && $c<=127? [format %c $c]: "."}]
        }
        puts [format "%8.8x  %-42s %s" $where $t2  $asc]
        incr where 16
    }
}

# convert string to hex
proc string2hex {string} {
    binary scan $string H* t
    regsub -all (..) $t "\\1\n" res
    return $res
}

set xml_ext ".xml"
set hex_ext "_xml.hex"

# step 1: create platform independent xml file name
set filename_xml [ file join misc $config$xml_ext ]
puts "Reading file $filename_xml"

# step 2: read file into memory
set data_xml [ readFile $filename_xml ]

# step 3: gzip compress
set data_gzip [zlib gzip $data_xml]
# hexdump $data_gzip

# step 4: convert binary to hex
set data_hex [ string2hex $data_gzip ]
# puts $data_hex

# step 5: writing out hex
set filename_hex [ file join misc $config$hex_ext ]
puts "Writing file $filename_hex"
set outfile [open $filename_hex w]
puts -nonewline $outfile $data_hex
close $outfile

# Exiting here will prevent the subsequent synthesis run. Useful for
# debugging of this script
# exit
