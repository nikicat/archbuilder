#archbuilder

It's a pretty simple bash script plus docker image to run AUR builds on a EC2 instance.

What it does is
 - allocates ec2 instance
 - runs docker container that builds provided packages using yay
 - fetches built packages back
 - terminates instance

Time to build linux kernel is about 20 minutes, cost is ~$0.07

What you need to run this script is a aws-cli-v2-bin linked to a working AWS account (with billing).
