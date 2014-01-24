#!/bin/bash

# sadly piuparts always returns with exit code 1 :((
sudo piuparts_wrapper $PWD/artifacts/*.deb || true

# generate TAP report
piuparts_tap piuparts.txt > piuparts.tap
