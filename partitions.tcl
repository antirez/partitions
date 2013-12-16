#!/usr/bin/tclsh
#
# Partitions.tcl -- simulate partitions in a network of computers.
#
# See COPYING file for copyright and license.

package require http

### Default config in case we are not able to load one via HTTP.

set ::peers {}
set ::max_block_time 20000
set ::partitions_per_hour 0
set ::myself {}
set ::clean_exit 0

# Global state

array set ::blocked {}
set ::tcp_port 12321
set ::pending_partition {}
set ::iteration 0
set ::old_config {}

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

### Networking.
#
# Partitions uses a simple server / client model to initiate new
# partitions among peers.

proc accept_clients {fd ip port} {
    fconfigure $fd -blocking 0
    set timeout 1000
    # We have 1 second to read the request or abort.
    while {$timeout > 0 && $::pending_partition eq {}} {
        set data [gets $fd]
        if {$data ne {}} {
            log "New partition request received from $ip:$port"
            set ::pending_partition $data
            # Validate if received data is a valid Tcl list and that
            # it makes sense.
            if {[catch {llength $::pending_partition}] ||
                [llength $::pending_partition] == 0} {
                set ::pending_partition {}
            }
            break
        }
        incr timeout -100
        after 100
    }
    close $fd
}

socket -server accept_clients $::tcp_port

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

# Create a new partition with us and the other peers we want to join with
# us in the partition.
#
# The partition will vary in size, and may be composed of just this host
# or N-1 hosts in total.
proc create_partition {} {
    # Can't proceed if I don't have my ip address.
    if {$::myself eq {}} return

    # Remove all the peers already partitioned away from me from the
    # list of peers.

    set p $::peers
    foreach ip [array names ::blocked] {
        set idx [lsearch -exact $ip $p]
        set p [lreplace $p $idx $idx]
    }

    # With less than 2 total peers  we can't create partitions.
    if {[llength $p] < 2} return

    # Remove myself from the list of peers
    set idx [lsearch -exact $p $::myself]
    set p [lreplace $p $idx $idx]

    # Select how many additional nodes we want in the new partition
    set additional [expr {int(rand()*([llength $p]-1))}]

    # Remove random elements to end with a list of length $additional
    while {[llength $p] > $additional} {
        set idx [expr {int(rand()*[llength $p])}]
        set p [lreplace $p $idx $idx]
    }

    # And myself of course
    lappend p $::myself

    # Set this as the new partition to apply, and communicate it to the
    # other peers I want to join the partition with me.
    # We use Tcl non blocking IO, the communication is best-effort since
    # some node may already be part of some other partition.
    log "Creating new partition ($p)"

    set ::pending_partition $p

    foreach ip $p {
        if {$ip eq $::myself} continue
        catch {
            set s [socket -async $ip $::tcp_port]
            fconfigure $s -blocking 0
            puts $s $p
            close $s
        }
        catch {close $s}
    }
}

# The Cron function is the core of the program and is called every
# 100 milliseconds in order to apply pending partitions, create new
# partitions, and so forth.
proc cron {} {
    # Refresh the configuration from time to time.
    if {($::iteration % 150) == 0} {
        flush stdout
        if {[catch {
            set token [::http::geturl $::config_url -timeout 5000]
            if {[::http::status $token] eq {timeout}} {
                log "Timeout from configuration server."
            } else {
                set new_config [::http::data $token]
                eval $new_config
                if {$new_config ne $::old_config} {
                    log "Configuration updated."
                }
                set ::old_config $new_config
                initialize
            }
            ::http::cleanup $token
        } err]} {
            puts $err
        }
    }
    incr ::iteration

    # Unblock blocked peers if timeout is reached
    foreach ip [array names ::blocked] {
        if {[info exists ::blocked($ip)]} {
            if {[clock milliseconds] > $::blocked($ip) || $::clean_exit} {
                if {[catch {firewall_unblock $ip} e]} {
                    puts "--- Firewalling layer error ---"
                    puts $e
                    puts "-------------------------------"
                }
                unset ::blocked($ip)
                log "Unblocking $ip."
            }
        }
    }

    # Create a new partition from time to time, if there is not already
    # a pending partition request to apply.
    if {$::pending_partition eq {} && [create_partition?]} create_partition

    # If there is a pending partition to apply, the pending variable
    # contains all the IPs of the partition we are joining, so we actually
    # need to block all the IPs not present in the list.
    if {$::pending_partition ne {}} {
        log "Entering the partition with $::pending_partition"
        foreach ip $::peers {
            if {$ip ne $::myself &&
                [lsearch -exact $::pending_partition $ip] == -1} \
            {
                set block_time [expr {int(rand()*$::max_block_time)}]
                incr block_time [clock milliseconds]
                if {[catch {firewall_block $ip} e]} {
                    puts "--- Firewalling layer error ---"
                    puts $e
                    puts "-------------------------------"
                }
                set ::blocked($ip) $block_time
                log "Blocking $ip."
            }
        }
        set ::pending_partition {}
    }

    if {$::clean_exit} {
        log "Clean exit, bye bye."
        exit 0
    }

    after 100 cron
}

proc main {} {
    if {[llength $::argv] != 1} {
        puts stderr "Usage: partitions.tcl http://config-server/config.txt"
        exit 1
    }
    set ::config_url [lindex $::argv 0]
    after 0 cron
    vwait forever
}

main
