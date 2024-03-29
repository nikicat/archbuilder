#!/bin/sh -e

source /usr/share/makepkg/util/message.sh

ami="${AMI:-ami-08056d04e24f84e34}"  # amzn2-ami-ecs-hvm-2.0.20220421-x86_64-ebs
spot=true
install=y
vcpus=32
sshkey=~/.local/auruild/ssh.pem
sockpath=~/.local/aurbuild/docker.sock
spot_options_path=${SPOT_OPTIONS_FILE:-/usr/share/aurbuild/spot-options.json}
name=aurbuild

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
        itype=c5a.$(($vcpus/4))xlarge
        [ $itype = c5a.1xlarge ] && itype=c5a.xlarge
        args="$@"
        if [ "$args" = "" ]; then
                print_usage
                exit 1
        fi
}

function cleanup() {
        rm -rf "$tmp_dir"
        rm -f "$sockpath"
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
        mkdir -p "$(dirname $sshkey)"
        if [ ! -e "$sshkey" ]; then
                if aws ec2 describe-key-pairs --key-names $name >/dev/null 2>&1; then
                        msg "Deleting old keypair..."
                        aws ec2 delete-key-pair --key-name $name >/dev/null
                fi
                msg "Creating keypair..."
                aws ec2 create-key-pair --key-name $name --query KeyMaterial --output text > "$sshkey"
                chmod go-rwx "$sshkey"
        fi
}

function run_instance() {
        if ! aws ec2 describe-security-groups --group-names $name >/dev/null 2>&1; then
                aws ec2 create-security-group --group-name $name --description $name > /dev/null
                aws ec2 authorize-security-group-ingress --group-name $name --protocol tcp --port 22 --cidr 0.0.0.0/0 > /dev/null
        fi
        [ "$spot" = "true" ] && market_options="--instance-market-options file://$spot_options_path"
        msg "Creating instance..."
        iid=$(aws ec2 run-instances --image-id $ami --instance-type $itype --count 1 --key-name $name --security-groups $name --query 'Instances[0].InstanceId' $market_options --output text)
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
        mkdir -p "$(dirname $sockpath)"
        [ -e $sockpath ] && rm $sockpath
        ssh -i "$sshkey" -fNT -L$sockpath:/run/docker.sock -o "StrictHostKeyChecking no" -o "ExitOnForwardFailure yes" -o "ConnectionAttempts 5" -o "LogLevel ERROR" ec2-user@$dns
        export DOCKER_HOST=unix://$sockpath
}

function build_and_download() {
        msg "Building packages..."
        local makeflags="-j$(($vcpus*2))"
        docker run -ti --tmpfs=/build:exec --env MAKEFLAGS=$makeflags --name $name nikicat/archbuild $args
        msg "Downloading packages..."
        tmp_dir=$(mktemp -d)
        docker cp $name:/packages $tmp_dir
        msg "Terminating instance..."
        aws ec2 terminate-instances --instance-id=$iid > /dev/null
        iid=
        if [ "$install" = y ]; then
                sudo pacman -U $tmp_dir/packages/*
        fi
        mv $tmp_dir/packages/* ./
}

colorize
parse_args "$@"
trap cleanup EXIT
trap echo INT
setup_keypair
run_instance
connect_docker
build_and_download "$@"
