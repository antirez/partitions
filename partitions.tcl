#!/usr/bin/tclsh
#
# Partitions.tcl -- simulate partitions in a network of computers.

package require http

### Default config in case we are not able to load one via HTTP.

set ::peers {}
set ::max_block_time 20000
set ::partitions_per_hour 0
set ::myself {}

# Global state

array set ::blocked {}

### Firewalling layer

set ::uname [string tolower [exec uname]]

# Minimal compatibility firewalling layer.
# It is only able to filter packets from/to a given IP address
# using iptables or ipfw depending on OS used.
#
# Firewalling API used:
#
# IPFW
#
# ipfw add 1000 deny src-ip 4.2.2.2/32
# ipfw add 2000 deny dst-ip 4.2.2.2/32
# ipvw del 1000
# ipvw del 2000
#
# IPTABLES
#
# iptables -A INPUT -p all -s 4.2.2.2/32 -j DROP
# iptables -A OUTPUT -p all -d 4.2.2.2/32 -j DROP
# iptables -D INPUT -p all -s 4.2.2.2/32 -j DROP
# iptables -D OUTPUT -p all -d 4.2.2.2/32 -j DROP

proc firewall_block ip {
    if {$::uname eq {darwin} || $::uname eq {freebsd}} {
        set i_rule_id [expr {1000+[lsearch $::peers $ip]}]
        set o_rule_id [expr {2000+[lsearch $::peers $ip]}]
        exec ipfw add $i_rule_id deny src-ip $ip/32
        exec ipfw add $o_rule_id deny dst-ip $ip/32
    } elseif {$::uname eq {linux}} {
        exec iptables -A INPUT -p all -s $ip/32 -j DROP
        exec iptables -A OUTPUT -p all -d $ip/32 -j DROP
    } else {
        error "Unsupported operating system $uname"
    }
}

proc firewall_unblock ip {
    if {$::uname eq {darwin} || $::uname eq {freebsd}} {
        set i_rule_id [expr {1000+[lsearch $::peers $ip]}]
        set o_rule_id [expr {2000+[lsearch $::peers $ip]}]
        exec ipfw del $i_rule_id
        exec ipfw del $o_rule_id
    } elseif {$::uname eq {linux}} {
        exec iptables -D INPUT -p all -s $ip/32 -j DROP
        exec iptables -D OUTPUT -p all -d $ip/32 -j DROP
    } else {
        error "Unsupported operating system $uname"
    }
}

### Utility functions

# This function finds what is this computer local address from the list
# of ::peers. It uses the trick of calling socket with the -myaddr option
# and check for error to see if there is or not a local interface with
# that IP address.
#
# If the local address is not found between the list of peers, an empty
# string is returned.
proc find_local_address {} {
    foreach ip $::peers {
        if {[catch {
            set s [socket -myaddr $ip $ip 1]
            # If we have a socket, must be one of our IPs.
            close $s
            return $ip
        } err]} {
            if {![string match {*requested address*} $err]} {
                # If the error is not about the address, it must be our IP.
                return $ip
            }
        }
    }
    return ""
}

### Main
#
# The main loop just selects with a given probability what address
# to block and for how much time.
#
# It also displays on screen who is blocked currently.

proc initialize {} {
    set ::myself [find_local_address]
    if {[info exists ::initialized]} return
    log "Partitions started, local IP is $::myself."
    set ::initialized 1
}

# Return the number of peers we are currently partitioned from
# (this only reports the peers we block, but the real reachability of
# other hosts could be limited by the fact that they are blocking
# us)
proc blocked_peers_num {} {
    array size ::blocked
}

# Log an event on screen. Always report the number of currently blocked peers.
proc log {msg} {
    puts "[clock format [clock seconds] -format {%b %d %H:%M:%S}] $msg ([blocked_peers_num] blocked)"
}

# Return true if we need to create a partition. This function assumes that
# we call it roughly ten times per second.
proc create_partition? {} {
    # The probability of creating a partition is given by the user configured
    # parameter ::partitions_per_hours divided by the number of peers in the
    # network, since every peer can create a partition.
    set pph [expr {double($::partitions_per_hour) / [llength $::peers]}]

    # If the probability of a partition per hour is $pph, the probability
    # of creating a partition every 0.1 seconds must be divided by
    # 36000, since 0.1 seconds is 36000 times smaller than 1 hour.
    set pph [expr {$pph/36000}]

    expr {rand() < $pph}
}

proc main {} {
    set iteration 0
    if {[llength $::argv] != 1} {
        puts stderr "Usage: partitions.tcl http://config-server/config.txt"
        exit 1
    }
    set ::config_url [lindex $::argv 0]

    while 1 {
        # Refresh the configuration from time to time.
        if {($iteration % 150) == 0} {
            puts -nonewline "Updating configuration... "
            flush stdout
            if {[catch {
                set token [::http::geturl $::config_url -timeout 5000]
                if {[::http::status $token] eq {timeout}} {
                    puts "timeout from server."
                } else {
                    eval [::http::data $token]
                    puts "configuration updated."
                    initialize
                }
                ::http::cleanup $token
            } err]} {
                puts $err
            }
        }
        incr iteration

        foreach ip $::peers {
            if {[info exists ::blocked($ip)]} {
                if {[clock milliseconds] > $::blocked($ip)} {
                    firewall_unblock $ip
                    unset ::blocked($ip)
                    log "Unblocking $ip"
                }
            } elseif {$ip ne $::myself} {
                if {[create_partition?]} {
                    set block_time [expr {int(rand()*$::max_block_time)}]
                    incr block_time [clock milliseconds]
                    firewall_block $ip
                    set ::blocked($ip) $block_time
                    log "Blocking $ip"
                }
            }
        }
        after 100
    }
}

main
