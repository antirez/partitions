Partitions.tcl
===

Partitions.tcl is a small Tcl program to simulate network partitions among a
set of real computers.

This is how it works:

* The program is executed in every computer that is part of the simulation.
* Using the firewalling layer (ipfw or iptables are supported) Partitions.tcl simulates different kinds of partitions.
* The configuration is provided to all the instances of Partitions.tcl via HTTP.
* Every instance of the program is a TCP server listening on port 12321 in order for the different instances being able to coordinate partitions together.

How to execute the program
---

You simply run the program with something like:

   ./partitions.tcl http://10.0.0.1/config.txt

The specified URL is supposed to return the `config.txt` file in order to
distribute the configuration to the different instances of the program.

An example of configuration is in the `config.txt` file shipped in this
software distribution.

Every time you change the `config.txt` file, the instances will upgrade
the configuration.

The configuration server can be one of the computers you use in the simulation
as usually it is not very important that the configuration is updated
promptly. Eventually simulated partitions heal so every peer will be able
to read the new configuration.

Partitions model
---

The program simulate the partitions by taking as parameter the probability
of partitions as partitions per hour, and the maximum duration of partitions.

At some point an instance starts a partition, and tries to get partitioned away
with a set of other nodes, so it contacts the other nodes asking to join
the partition. Nodes join a partition by filtering all the nodes but the
ones in the partition they want to join.

Every node receiving a partition to join, currently selects its own duration
for the partition time, between 0 and the maximum configured value.

Sub-partitions are possible as well. For example we may have five computers
A, B, C, D, E. After some time A tries to create a partition with A, B, C.

Later B may try to join a partition with it alone, and for a different time
compared to the original partition. So initially we have a partition like:

A B C | D E

That later will evolve into

A C | B | D E

Because every node selects its own partition duration, the actual
transitions between one partition and the other involves entering other
partitions setups.

Sub-partitions have a smaller probability to happen in the model used
by Partition.tcl. Specifically the probability of a sub partition is reduced
proportionally to the number of nodes already partitioned from the instance.

Development
---

This software is currently experimental and is used to simulate partitions
in order to test Redis Cluster. Pull requests in order to improve the program
are welcomed.


