#!/bin/sh -exv

TYPE=c5a.4xlarge
VCPUS=16
J=$(($VCPUS*2))
AMI=ami-08056d04e24f84e34  # amzn2-ami-ecs-hvm-2.0.20220421-x86_64-ebs
spot=true

export AWS_PAGER=""

trap cleanup EXIT

function cleanup()
{
        [ -e docker.sock ] && rm docker.sock
        [ "$iid" != "" ] && aws ec2 terminate-instances --instance-id=$iid
        if [ "$spot_price" != "" ]
        then
                tend=$(date +%s)
                echo "Cost: \$$((($tend - $tstart) * $spot_price / 3600))"
        fi
}

function setup_keypair() {
        [ -e ssh.pem ] || aws ec2 create-key-pair --key-name archbuild --query KeyMaterial --output text > ssh.pem
        chmod go-rwx ssh.pem
}

function run_instance() {
        aws ec2 create-security-group --group-name archbuild --description archbuild && aws ec2 authorize-security-group-ingress --group-name archbuild --protocol tcp --port 22 --cidr 0.0.0.0/0 || true
        [ "$spot" = "true" ] && market_options="--instance-market-options file://spot-options.json"
        iid=$(aws ec2 run-instances --image-id $AMI --instance-type $TYPE --count 1 --key-name archbuild --security-groups archbuild --query 'Instances[0].InstanceId' $market_options --output text)
        dns=$(aws ec2 describe-instances --instance-id $iid --query 'Reservations[0].Instances[0].PublicDnsName' --output text)
        az=$(aws ec2 describe-instances --instance-id $iid --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)
        tstart=$(date +%s)
        spot_price=$(aws ec2 describe-spot-price-history --instance-types=$TYPE --availability-zone=$az --product-descriptions=Linux/UNIX --start-time=$tstart --end-time=$tstart --no-cli-pager  --query 'SpotPriceHistory[0].SpotPrice' --output text)
}

function connect_docker() {
        [ -e docker.sock ] && rm docker.sock
        ssh -i ./ssh.pem -fNT -L./docker.sock:/run/docker.sock -o "StrictHostKeyChecking no" -o "ExitOnForwardFailure yes" ec2-user@$dns
        export DOCKER_HOST=unix://./docker.sock
}

function build_and_download() {
        docker run -ti --tmpfs=/build:exec --env MAKEFLAGS=-j$J --name archbuild nikicat/archbuild $* 
        docker cp archbuild:/packages ./
}

setup_keypair
run_instance
connect_docker
build_and_download $*
