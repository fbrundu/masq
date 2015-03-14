Simple tool to create a bridge between two hosts and share one connection :)

Host A forwards host B's packets.

Internet <- -> A <- -> B

### How to use (versions > 0.2)
Start masq.sh with

`sudo masq.sh client|server start [options]`

### How to use (versions <= 0.2)
Start masq-master.sh on host A and masq-slave.sh on host B

### Built-in Help
Start masq.sh with no arguments
