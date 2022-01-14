﻿#!/bin/bash

# Copyright The Helm Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -x
set -o errexit
set -o nounset
set -o pipefail

show_help() {
cat << EOF
Usage: $(basename "$0") <options>
    -h, --help                    Display help
    -v, --version                 The chart version to use (default: latest)"
    -w, --wait-for-healthcheck    Wait for healthcheck after deploynment
    -c, --chart                   Chart name 
    -r, --release                 Release name
    -u, --use-webcaller           Initialize using webcaller after healthcheck
    -p, --pod-dns                 dns name to construct webcaller call. defaults to release name
    -a, --webcaller-account       account for webcaller request
    -d, --deploy-regions          list of regions to deploy to, comma separated
EOF
}

main() {
    local version="latest"
    local chart=
    local release=
    local wait_hc=
    local use_wc=
    local pod_dns=
    local wc_acct=
    local regions="na,fr,sg"

    parse_command_line "$@"


   for region in ${regions//,/ }
   do
     sv_enabled=$(cat ./.github/pipeline.json | jq -r ".prod.$region.enabled")
      if [ "$sv_enabled" = true ] ; then 
        address=$(cat ./.github/pipeline.json | jq -r ".prod.$region.address")
        if [[ -z "$address" || "$address" == "null" ]]; then
            address=$(cat ./.github/pipeline.json | jq -r ".prod.$region.ip_address")
        fi
      fi;
     deploy_chart "$address"
   done
   
}

parse_command_line() {
    while :; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit
                ;;
            -c|--chart)
                if [[ -n "${2:-}" ]]; then
                    chart="$2"
                    shift
                else
                    echo "ERROR: '--config' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -v|--version)
                if [[ -n "${2:-}" ]]; then
                    version="$2"
                    shift
                else
                    echo "ERROR: '-v|--version' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -r|--release)
                if [[ -n "${2:-}" ]]; then
                    release="$2"
                    shift
                else
                    echo "ERROR: '-r|--release' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -w|--wait-for-healthcheck)
                wait_hc="true"                
                ;;
            -d|--deploy-regions)
                if [[ -n "${2:-}" ]]; then
                    regions="$2"
                    shift
                else
                    echo "ERROR: '-d|--deploy-regions' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -p|--pod-dns)
                if [[ -n "${2:-}" ]]; then
                    pod_dns="$2"
                    shift
                else
                    echo "ERROR: '----pod-dns' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -a|--webcaller-account)
                if [[ -n "${2:-}" ]]; then
                    wc_acct="$2"
                    shift
                else
                    echo "ERROR: '----webcaller-account' cannot be empty." >&2
                    show_help
                    exit 1
                fi
                ;;
            -u|--use-webcaller)
                use_wc="true"
                shift
                ;;
            *)
                break
                ;;
        esac

        shift
    done

    if [[ -z "$chart" ]]; then
        echo "ERROR: '-c|--chart' is required." >&2
        show_help
        exit 1
    fi

    if [[ -z "$release" ]]; then
        release=$chart
    fi
    if [[ -z "$pod_dns" ]]; then
        pod_dns=$chart
    fi
    if [[ -z "$wc_acct" ]]; then
        wc_acct="nama.$chart"
    fi

}


deploy_chart() {
    local address="$1"
    echo -e "${SSH_DEPLOY_KEY//\s+/\\n}" > .key
    chmod 600 .key 
cat <<EOF >> .deploy_script
    set -e; set -x;
    echo "[\$(date -Is)] Deploying..."
    helm repo update    
    export installed=\$(helm list -f "^$release\$" -q)
    echo "Searching for release=\$installed"
     if [[ -z "\$installed" ]]; then
         echo "[\$(date -Is)] Installing namachain/$chart as release name $release at version $version"
         helm install $release namachain/$chart --version $version
    else
         echo "[\$(date -Is)] attempting to upgrade $release to version $version..."
         helm upgrade $release namachain/$chart --version $version
     fi
   
    if [[ -n "$wait_hc" ]]; then
      kubectl wait --for=condition=Available --timeout=20s deployment.apps/$chart
    fi
    if [[ -n "$use_wc" ]]; then
      kubectl exec -i -t webcaller \
        -- curl --location --request POST http://vault:80/api/service/deploy --header "Content-Type: application/json" --data-raw "{\"baseUrl\":\"http://$pod_dns:80\",\"account\":\"$wc_acct\"}"
    fi
    echo "[\$(date -Is)] Deployment completed."

EOF
    echo "Executing on server: $(cat .deploy_script)"
    cat .deploy_script | ssh -oStrictHostKeyChecking=no -i ./.key nama@$address bash 
    rm -f .key .deploy-script 
}

main "$@"