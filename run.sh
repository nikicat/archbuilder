#!/bin/sh -e

source /usr/share/makepkg/util/message.sh

ami="${AMI:-ami-08056d04e24f84e34}"  # amzn2-ami-ecs-hvm-2.0.20220421-x86_64-ebs
spot=true
install=y
vcpus=32

export AWS_PAGER=""

function print_usage() {
        echo "$0 [-c <vcpus>] [-d] [-h] <packages>"
        echo "   -c <vcpus>   count of VCPU to create VM instance with. Less vcpu - more efficient, but longer build. Default is 32."
        echo "   -d           download build package only (do not install)"
        echo "   -h           show this help"
}

function parse_args() {
        [ $# = 0 ] && print_usage && exit
        while [[ $# -gt 0 ]]; do
                case $1 in
                -c)
                        vcpus=$2
                        shift
                        shift
                        valid_vcpus="4 8 16 32 64 96"
                        if [[ ! " $valid_vcpus " =~ " $vcpus " ]]; then
                                error "Invalid vcpus value. Possible values are ($valid_vcpus)"
                                exit 1
                        fi
                        itype=c5a.$(($vcpus/4))xlarge
                        [ $itype = c5a.1xlarge ] && itype=c5a.xlarge
                        ;;
                -d)
                        install=n
                        shift
                        ;;
                -h)
                        print_usage
                        exit 0
                        ;;
                -*)
                        error "Unknown option $1"
                        exit 1
                        ;;
                *)
                        break
                        ;;
                esac
        done
        args="$@"
        if [ $args = "" ]; then
                print_usage
                exit 1
        fi
}

function cleanup() {
        #jobs %_spinner 2>/dev/null && kill %_spinner && wait %_spinner || true
        [ "$tmp_dir" != "" ] && rm -r "$tmp_dir"
        [ -e docker.sock ] && rm docker.sock
        if [ "$iid" != "" ]; then
                warning "emergency terminating instance..."
                aws ec2 terminate-instances --instance-id=$iid > /dev/null
        fi
        if [ "$spot_price" != "" ]
        then
                tend=$(date +%s)
                time=$(($tend - $tstart))
                cost=$(echo "scale=4;$time * $spot_price / 3600" | bc)
                time_text=$(date -ud "@$time" +'%H:%M:%S')
                echo "Total time: $time_text. Cost: \$$cost"
        fi
}

function setup_keypair() {
        if [ ! -e ssh.pem ]; then
                msg "Creating keypair..."
                aws ec2 create-key-pair --key-name archbuild --query KeyMaterial --output text > ssh.pem
        fi
        chmod go-rwx ssh.pem
}

function run_instance() {
        aws ec2 describe-security-groups --group-names archbuild >/dev/null || (aws ec2 create-security-group --group-name archbuild --description archbuild > /dev/null && aws ec2 authorize-security-group-ingress --group-name archbuild --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null)
        [ "$spot" = "true" ] && market_options="--instance-market-options file://spot-options.json"
        msg "Creating instance..."
        iid=$(aws ec2 run-instances --image-id $ami --instance-type $itype --count 1 --key-name archbuild --security-groups archbuild --query 'Instances[0].InstanceId' $market_options --output text)
        msg "Waiting for instance to start..."
        while true; do
                state=$(aws ec2 describe-instances --filter Name=instance-id,Values=$iid --query 'Reservations[*].Instances[*].State.Name' --output text)
                [ "$state" = "running" ] && break
                sleep 1
        done
        dns=$(aws ec2 describe-instances --instance-id $iid --query 'Reservations[0].Instances[0].PublicDnsName' --output text)
        az=$(aws ec2 describe-instances --instance-id $iid --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)
        tstart=$(date +%s)
        spot_price=$(aws ec2 describe-spot-price-history --instance-types=$itype --availability-zone=$az --product-descriptions=Linux/UNIX --start-time=$tstart --end-time=$tstart --no-cli-pager  --query 'SpotPriceHistory[0].SpotPrice' --output text)
}

function connect_docker() {
        msg "Connecting ssh..."
        [ -e docker.sock ] && rm docker.sock
        ssh -i ./ssh.pem -fNT -L./docker.sock:/run/docker.sock -o "StrictHostKeyChecking no" -o "ExitOnForwardFailure yes" -o "ConnectionAttempts 5" -o "LogLevel ERROR" ec2-user@$dns
        export DOCKER_HOST=unix://./docker.sock
}

function build_and_download() {
        msg "Building packages..."
        local makeflags="-j$(($vcpus*2))"
        docker run -ti --tmpfs=/build:exec --env MAKEFLAGS=$makeflags --name archbuild nikicat/archbuild $args
        msg "Downloading packages..."
        tmp_dir=$(mktemp -d -p ./)
        docker cp archbuild:/packages $tmp_dir
        msg "Terminating instance..."
        aws ec2 terminate-instances --instance-id=$iid > /dev/null
        iid=
        if [ "$install" = y ]; then
                sudo pacman -U $tmp_dir/packages/*
        fi
        mv $tmp_dir/packages/* ./packages
}

colorize
parse_args "$@"
trap cleanup EXIT
trap echo INT
setup_keypair
run_instance
connect_docker
build_and_download "$@"
