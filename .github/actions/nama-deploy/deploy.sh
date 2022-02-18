#!/bin/bash

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
    -e, --env                     Environment (Prod, Testnet) 
    -r, --release                 Release name
    -u, --use-webcaller           Initialize using webcaller after healthcheck
    -p, --pod-dns                 dns name to construct webcaller call. defaults to release name
    -a, --webcaller-account       account for webcaller request
    -d, --deploy-regions          list of regions to deploy to, comma separated
    -f, --force-redeploy          Force a redeployment even if there are no chart updates and image tag is the same
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
    local force_redeploy=
    local regions="ny"
    local env="Testnet"
    parse_command_line "$@"


   for region in ${regions//,/ }
   do
     sv_enabled=$(cat ./.github/env.json | jq -r ".$env.$region.enabled")
      if [ "$sv_enabled" = "true" ] ; then 
        address=$(cat ./.github/env.json | jq -r ".$env.$region.address")
        if [[ -z "$address" || "$address" == "null" ]]; then
            address=$(cat ./.github/env.json | jq -r ".prod.$region.ip_address")
        fi
      fi;
    echo "Deploying to $env/$region"
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
            -e|--env)
                if [[ -n "${2:-}" ]]; then
                    env="$2"
                    shift
                else
                    echo "ERROR: '--env' cannot be empty." >&2
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
                ;;
            -f|--force-redeploy)
                force_redeploy="true"
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
cat <<EOF > .deploy_script
    set -e; set -x;
    echo "[\$(date -Is)] Deploying..."
    helm repo update
    ts=\$(date +%s)
    mkdir -p /home/nama/deploy/\$ts && cd /home/nama/deploy/\$ts && echo "Deploying from \$ts"
    helm pull namachain/$chart --version $version --untar
    export installed=\$(helm list -f "^$release\$" -q)
    echo "Searching for release=\$installed"
    ver="$version"
    if [[ -z "\$ver" ]]; then
        ver="latest-stable"
    fi
    if [ "\$ver" = "latest" ]; then
      ver=\$(helm search repo namachain --devel | grep namachain/$chart | awk '{print \$2}')
    fi
    if [ "\$ver" = "latest-stable" ]; then
      ver=\$(helm search repo namachain | grep namachain/$chart | awk '{print \$2}')
    fi
    if [[ -z "\$installed" || "$force_redeploy" = "true"  ]]; then
        if [[ -n "\$installed" ]]; then
            helm uninstall $release
        fi
         echo "[\$(date -Is)] Installing namachain/$chart as release name $release at version $version"
         touch ./$chart/values-${env}.yaml
         helm install $release ./$chart -f ./$chart/values-${env}.yaml --version $ver --set environment=${env}
    else
         echo "[\$(date -Is)] attempting to upgrade $release to version $version..."
         helm upgrade $release ./$chart -f ./$chart/values-${env}.yaml --version $ver --set environment=${env}
     fi
   
    if [[ -n "$wait_hc" ]]; then
      sleep 5s
      kubectl wait --for=condition=Available --timeout=90s deployment.apps/$chart
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
