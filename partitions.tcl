#!/usr/bin/tclsh
#
# Partitions.tcl -- simulate partitions in a network of computers.

### Configuration parameters

set ::peers {
    192.168.1.10
    192.168.1.28
    192.168.1.39
    192.168.1.40
    192.168.1.42
    192.168.1.43
}

set ::max_block_time 20000

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
    log "Partitions started, local IP is $::myself."
}

proc log {msg} {
    puts "[clock format [clock seconds] -format {%b %d %H:%M:%S}] $msg"
}

proc main {} {
    initialize

    while 1 {
        array set blocked {}

        foreach ip $::peers {
            if {[info exists blocked($ip)]} {
                if {[clock milliseconds] > $blocked($ip)} {
                    firewall_unblock $ip
                    unset blocked($ip)
                    log "Unblocking $ip"
                }
            } elseif {$ip ne $::myself} {
                if {rand() < 0.001} {
                    set block_time [expr {int(rand()*$::max_block_time)}]
                    incr block_time [clock milliseconds]
                    firewall_block $ip
                    set blocked($ip) $block_time
                    log "Blocking $ip"
                }
            }
        }
        after 100
    }
}

main
