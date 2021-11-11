#!/bin/bash

dockerFile=""
context="default"
services=()
hasServices="false"
remote=""
images=()
startPhase="build"
project=""
while getopts ":f:c:s:r:i:p:nh" opt; do
    case $opt in
        f)
            dockerFile="-f $OPTARG";
            ;;
        c)
            context="$OPTARG";
            ;;
        r)
            remote=$OPTARG;
            ;;
        s)
            services+=(${OPTARG//,/ });
            hasServices="true";
            ;;
        i)
            images+=(${OPTARG//,/ });
            ;;
        n)
            startPhase="deploy";
            ;;
        p)
            project="-p $OPTARG";
            ;;
        h)
            echo "options:";
            echo "f path to docker compose file";
            echo "c docker context to use";
            echo "s comma separated services to deploy";
            echo "r remote connection details for copying images";
            echo "i comma separated images to copy to remote, requires r";
            echo "n no build, skip the building of service images";
            echo "p project name";
            exit 0;
    esac
done

if [[ $startPhase = "build" ]]; then
    echo "docker context use default"
    docker context use default

    echo "docker-compose $dockerFile build --parallel --no-cache --force-rm ${services[@]}"
    docker-compose $dockerFile build --parallel --no-cache --force-rm ${services[@]}

    echo "yes | docker image prune"
    yes | docker image prune
fi

if [[ -n "$remote" ]]; then
    echo "docker save ${images[@]} | ssh $remote -C docker load"
    docker --context default save ${images[@]} | ssh $remote -C docker load
fi

echo "docker context use $context"
docker context use $context

if [[ $hasServices = "true" ]]; then
    echo "docker-compose $project $dockerFile stop ${services[@]}"
    docker-compose $project  $dockerFile stop ${services[@]}

    echo "docker-compose $project $dockerFile rm -f ${services[@]}"
    docker-compose $project  $dockerFile rm -f ${services[@]}
else
    echo "docker-compose $project $dockerFile down"
    docker-compose $project $dockerFile down -v
fi

echo "yes | docker image prune"

echo "docker-compose $project $dockerFile up --no-recreate -d ${services[@]}"
docker-compose $project $dockerFile up --no-recreate -d ${services[@]}

echo "docker context use default"
docker context use default