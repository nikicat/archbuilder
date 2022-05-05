#!/bin/sh -e

source ./vendor/bash-spinner/spinner.sh

ami="${AMI:-ami-08056d04e24f84e34}"  # amzn2-ami-ecs-hvm-2.0.20220421-x86_64-ebs
spot=true
install=y

export AWS_PAGER=""

function print_usage() {
        echo "$0 [-c <vcpus>] <packages>"
        echo " -c <vcpus> - count of VCPU to create VM instance with. Less vcpu - more efficient, but longer build. Default is 32."
}

function parse_args() {
        vcpus=32
        to_shift=0
        if [ "$1" = "-c" ]; then
                vcpus=$2
                to_shift=2
        fi
        case $vcpus in
                4)
                        type=c5a.xlarge
                        ;;
                8)
                        type=c5a.2xlarge
                        ;;
                16)
                        type=c5a.4xlarge
                        ;;
                32)
                        type=c5a.8xlarge
                        ;;
                48)
                        type=c5a.12xlarge
                        ;;
                64)
                        type=c5a.16xlarge
                        ;;
                96)
                        type=c5a.24xlarge
                        ;;
                *)
                        echo "Invalid vcpus value. Possible values are (4,8,16,32)"
                        exit 1
                        ;;
        esac
        j=$(($vcpus*2))
}

function cleanup()
{
        stop_spinner 0
        [ "$tmp_dir" != "" ] && rm -r "$tmp_dir"
        [ -e docker.sock ] && rm docker.sock
        [ "$iid" != "" ] && aws ec2 terminate-instances --instance-id=$iid > /dev/null
        if [ "$spot_price" != "" ]
        then
                tend=$(date +%s)
                time=$(($tend - $tstart))
                cost=$(echo "scale=4;$time * $spot_price / 3600" | bc)
                echo "Time: $time sec. Cost: \$$cost"
        fi
}

function setup_keypair() {
        if [ ! -e ssh.pem ]; then
                start_spinner "creating keypair..."
                aws ec2 create-key-pair --key-name archbuild --query KeyMaterial --output text > ssh.pem
                stop_spinner $?
        fi
        chmod go-rwx ssh.pem
}

function run_instance() {
        aws ec2 describe-security-groups --group-names archbuild >/dev/null || (aws ec2 create-security-group --group-name archbuild --description archbuild > /dev/null && aws ec2 authorize-security-group-ingress --group-name archbuild --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null)
        [ "$spot" = "true" ] && market_options="--instance-market-options file://spot-options.json"
        start_spinner "creating instance..."
        iid=$(aws ec2 run-instances --image-id $ami --instance-type $type --count 1 --key-name archbuild --security-groups archbuild --query 'Instances[0].InstanceId' $market_options --output text)
        stop_spinner $?
        start_spinner "waiting for instance to start..."
        while true; do
                state=$(aws ec2 describe-instances --filter Name=instance-id,Values=$iid --query 'Reservations[*].Instances[*].State.Name' --output text)
                [ "$state" = "running" ] && break
                sleep 1
        done
        dns=$(aws ec2 describe-instances --instance-id $iid --query 'Reservations[0].Instances[0].PublicDnsName' --output text)
        az=$(aws ec2 describe-instances --instance-id $iid --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)
        tstart=$(date +%s)
        spot_price=$(aws ec2 describe-spot-price-history --instance-types=$type --availability-zone=$az --product-descriptions=Linux/UNIX --start-time=$tstart --end-time=$tstart --no-cli-pager  --query 'SpotPriceHistory[0].SpotPrice' --output text)
        stop_spinner $?
}

function connect_docker() {
        start_spinner "connecting ssh..."
        [ -e docker.sock ] && rm docker.sock
        ssh -i ./ssh.pem -fNT -L./docker.sock:/run/docker.sock -o "StrictHostKeyChecking no" -o "ExitOnForwardFailure yes" -o "ConnectionAttempts 5" -o "LogLevel ERROR" ec2-user@$dns
        export DOCKER_HOST=unix://./docker.sock
        stop_spinner $?
}

function build_and_download() {
        echo "building packages..."
        docker run -ti --tmpfs=/build:exec --env MAKEFLAGS=-j$j --name archbuild nikicat/archbuild "$@"
        start_spinner "downloading pacakges..."
        tmp_dir=$(mktemp -d -p ./)
        docker cp archbuild:/packages $tmp_dir
        stop_spinner $?
        if [ "$install" = y ]; then
                sudo pacman -U $tmp_dir/packages/*
        fi
        mv $tmp_dir/packages/* ./packages
}

if [ "$1" = "" ]; then
        print_usage
        exit
fi
parse_args "$@"
shift $to_shift
setup_keypair
trap cleanup EXIT
run_instance
connect_docker
build_and_download "$@"
