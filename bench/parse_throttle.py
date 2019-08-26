#!/usr/bin/env python2

# From https://harlemsquirrel.github.io/shell/2019/01/05/monitoring-raspberry-pi-power-and-thermal-issues.html with some modifications

import subprocess

GET_THROTTLED_CMD = 'vcgencmd get_throttled'
MESSAGES = {
    0: 'Under-voltage!',
    1: 'ARM frequency capped!',
    2: 'Currently throttled!',
    3: 'Soft temperature reached!',
    16: 'Under-voltage has occurred since last reboot.',
    17: 'Throttling has occurred since last reboot.',
    18: 'ARM frequency capped has occurred since last reboot.',
    19: 'Soft temperature reached since last reboot.'
}

print("Checking for throttling issues since last reboot...")

throttled_output = subprocess.check_output(GET_THROTTLED_CMD, shell=True)
throttled_binary = bin(int(throttled_output.split('=')[1], 0))

for position, message in MESSAGES.iteritems():
    # Check for the binary digits to be "on" for each warning message
    if len(throttled_binary) > position and throttled_binary[0 - position - 1] == '1':
        print(message)
