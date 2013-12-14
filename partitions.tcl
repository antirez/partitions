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

set ::myself 192.168.1.10
set ::max_block_time 20000

###############################################################################

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

# The main loop just selects with a given probability what address
# to block and for how much time.
#
# It also displays on screen who is blocked currently.

while 1 {
    array set blocked {}

    puts -nonewline "\x1b\[H\x1b\[2J"; # Clear screen
    puts "Currently blocked IPs:"
    foreach ip $::peers {
        if {[info exists blocked($ip)]} {
            puts "BLOCKED $ip"
            if {[clock milliseconds] > $blocked($ip)} {
                firewall_unblock $ip
                unset blocked($ip)
            }
        } elseif {$ip ne $::myself} {
            if {rand() < 0.001} {
                set block_time [expr {int(rand()*$::max_block_time)}]
                incr block_time [clock milliseconds]
                firewall_block $ip
                set blocked($ip) $block_time
            }
        }
    }
    after 100
}
