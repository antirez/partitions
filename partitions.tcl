#!/usr/bin/tclsh
#
# sudo ipfw add 1000 deny src-ip 4.2.2.2/32
# sudo ipvw del 1000

set ::uname [string tolower [exec uname]]

set ::peers {
    192.168.1.10
    192.168.1.28
    192.168.1.39
    192.168.1.40
    192.168.1.42
    192.168.1.43
}

set ::myself 192.168.1.28
set ::max_block_time 20000

# Minimal compatibility firewalling layer.
# It is only able to filter packets from/to a given IP address
# using iptables or ipfw depending on OS used.

proc firewall_block ip {
    set i_rule_id [expr {1000+[lsearch $::peers $ip]}]
    set o_rule_id [expr {2000+[lsearch $::peers $ip]}]

    if {$::uname eq {darwin} || $::uname eq {freebsd}} {
        exec ipfw add $i_rule_id deny src-ip $ip/32
        exec ipfw add $o_rule_id deny dst-ip $ip/32
    } elseif {$::uname eq {linux}} {
    } else {
        error "Unsupported operating system $uname"
    }
}

proc firewall_unblock ip {
    set i_rule_id [expr {1000+[lsearch $::peers $ip]}]
    set o_rule_id [expr {2000+[lsearch $::peers $ip]}]

    if {$::uname eq {darwin} || $::uname eq {freebsd}} {
        exec ipfw del $i_rule_id
        exec ipfw del $o_rule_id
    } elseif {$::uname eq {linux}} {
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
