#! /bin/bash

# set -e
set -x

# TODO: replace this with the full path to the executable
CIVO_BIN="${CIVO_EXE:-civo}"
CIVO_TOKEN="${CIVO_TOKEN:-}"
YQ_BIN="yq"
APP_NAME=test # TODO: make this a parameter
REGION="${CIVO_REGION:-LON1}"
# TODO: check for curl

export appName=${APP_NAME}

 # From stackoverflow:
 # https://stackoverflow.com/questions/6569478/detect-if-executable-file-is-on-users-path/53798785#53798785
function is_bin_in_path {
  if [[ -n $ZSH_VERSION ]]; then
    builtin whence -p "$1" &> /dev/null
  else  # bash:
    builtin type -P "$1" &> /dev/null
  fi
}

# Make sure the civo token has been set
if [[ -z ${CIVO_TOKEN} ]]; then
    printf "You must set the CIVO_TOKEN environment variable to your Civo API key"
    exit 1
fi

is_bin_in_path ${CIVO_BIN}

if [[ $? -eq 0 ]]; then
    printf "Found ${CIVO_BIN} executable\n"
else
    printf "No ${CIVO_BIN}\n"
    printf "Install with command:\n"
    printf "\tcurl -sL https://civo.com/get | sh\n"
    exit 1
fi

is_bin_in_path ${YQ_BIN}

if [[ $? -eq 0 ]]; then
    printf "Found ${YQ_BIN} executable\n"
else
    printf "No ${YQ_BIN}\n"
    printf "Find install instructions here: https://mikefarah.gitbook.io/yq/\n"
    exit 1
fi

# Network #

NETWORK_ID=`export appName=${APP_NAME} && \
    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
    "https://api.civo.com/v2/networks?region=${REGION}" | 
    yq -r -ojson '.[] | select(.label == env(appName)) | .id'`

if [[ -z ${NETWORK_ID} ]]; then
    printf "No network named ${APP_NAME}\n"
    
    # add yes/no input here
    printf "Would you like to create a network named ${APP_NAME}?\n\n"
    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
    "https://api.civo.com/v2/networks?region=${REGION}" -d label=${APP_NAME}

    # loop while this is pending
    NETWORK_STATUS=`export appName=${APP_NAME} && \
        curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/networks?region=${REGION}" | 
        yq -r -ojson '.[] | select(.label == env(appName)) | .status'`

    while [[ NETWORK_STATUS -ne "Active" ]]
    do
        printf "Network status: ${NETWORK_STATUS}\n"
        sleep 5
        NETWORK_STATUS=`export appName=${APP_NAME} && \
            curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
            "https://api.civo.com/v2/networks?region=${REGION}" | 
            yq -r -ojson '.[] | select(.label == env(appName)) | .status'`
    done

    NETWORK_ID=`export appName=${APP_NAME} && \
        curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/networks?region=${REGION}" | 
        yq -r -ojson '.[] | select(.label == env(appName)) | .id'`
fi

# Firewall #

FW_ID=`export appName=${APP_NAME} && \
    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
    "https://api.civo.com/v2/firewalls?region=${REGION}" |
    yq -r -ojson '.[] | select(.name == env(appName)) | .id'`

if [[ -z ${FW_ID} ]]; then
    printf "No fw named ${APP_NAME}\n"
    
    # add yes/no input here
    printf "Would you like to create a fw named ${APP_NAME}?\n\n"
    
    curl -H "Authorization: bearer ${CIVO_TOKEN}" https://api.civo.com/v2/firewalls \
    -d "name=${APP_NAME}&network_id=${NETWORK_ID}&region=${REGION}"

    # loop while this is pending
    FW_EXISTS=`export appName=${APP_NAME} && \
        curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/firewalls?region=${REGION}" |
        yq -r -ojson '.[] | select(.name == env(appName)) | .name'`

    while [[ -z ${FW_EXISTS} ]]
    do
        printf "firewall status: ${FW_EXISTS}\n"
        sleep 30
        FW_EXISTS=`export appName=${APP_NAME} && \
            curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
            "https://api.civo.com/v2/firewalls?region=${REGION}" |
            yq -r -ojson '.[] | select(.name == env(appName)) | .name'`
    done

    FW_ID=`export appName=${APP_NAME} && \
        curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/firewalls?region=${REGION}" |
        yq -r -ojson '.[] | select(.name == env(appName)) | .id'`

    # create some firewall rules
    # TODO: get local IP and optionally apply it as a x.x.x.x/32 address
    echo "Creating some rules"
    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/firewalls/${FW_ID}/rules" \
        -d "region=${REGION}&start_port=5432&end_port=5432&label=${APP_NAME}&action=allow&protocol=tcp"
    
    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/firewalls/${FW_ID}/rules" \
        -d "region=${REGION}&start_port=80&end_port=80&label=${APP_NAME}&action=allow&protocol=tcp"
    
    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/firewalls/${FW_ID}/rules" \
        -d "region=${REGION}&start_port=443&end_port=443&label=${APP_NAME}&action=allow&protocol=tcp"

    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/firewalls/${FW_ID}/rules" \
        -d "region=${REGION}&start_port=6443&end_port=6443&label=${APP_NAME}&action=allow&protocol=tcp"
        
    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/firewalls/${FW_ID}/rules" \
        -d "region=${REGION}&start_port=5432&end_port=5432&label=${APP_NAME}&action=allow&protocol=udp"

    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/firewalls/${FW_ID}/rules" \
        -d "region=${REGION}&start_port=1&end_port=65535&label=${APP_NAME}&direction=egress&action=allow&protocol=tcp"

    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/firewalls/${FW_ID}/rules" \
        -d "region=${REGION}&start_port=1&end_port=65535&label=${APP_NAME}&direction=egress&action=allow&protocol=udp"


    # TODO: remove the rules that allow access from 0.0.0.0/0
fi

# Database #

DB_ID=`export appName=${APP_NAME} &&
    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
    "https://api.civo.com/v2/databases?region=${REGION}" |
    yq -r -ojson '.items[] | select(.name == env(appName)) | .name'`


if [[ -z ${DB_ID} ]]; then
    printf "No database named ${APP_NAME}\n"
    
    # add yes/no input here
    printf "Would you like to create a database named ${APP_NAME}?\n\n"
    printf "Using network ${NETWORK_ID} and firewall ${FW_ID}\n\n"

    curl -s -X POST -H "Authorization: bearer ${CIVO_TOKEN}" \
    "https://api.civo.com/v2/databases" \
    -d "name=${APP_NAME}&region=${REGION}&software=PostgreSQL&software_version=14&size=g3.db.small&network_id=${NETWORK_ID}&firewall_id=${FW_ID}&firewall_rule=5432"


    # loop while this is pending
    DB_STATUS=`export appName=${APP_NAME} &&
        curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/databases?region=${REGION}" |
        yq -r -ojson '.items[] | select(.name == env(appName)) | .status'`

    while [[ "${DB_STATUS}" == "Pending" ]]
    do
        printf "DB Status: ${DB_STATUS}, sleeping\n\n"
        sleep 90
        DB_STATUS=`export appName=${APP_NAME} &&
            curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
            "https://api.civo.com/v2/databases?region=${REGION}" |
            yq -r -ojson '.items[] | select(.name == env(appName)) | .status'`
    done

    # when done pending get creds
    ${CIVO_BIN} db cred ${APP_NAME} -ojson --region ${REGION} > "CIVO_${APP_NAME}_DB.json"
fi

# Kubernetes #

K8S_CLUSTER_ID=`export appName=${APP_NAME} && \
    curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
    https://api.civo.com/v2/kubernetes/clusters?region=${REGION} |
    yq -r -ojson '.items[] | select(.name == env(appName)) | .name'`

if [[ -z ${K8S_CLUSTER_ID} ]]; then
    printf "No kubernetes cluster named ${APP_NAME}\n"

    # add yes/no input here
    printf "Would you like to create a cluster named ${APP_NAME}\n\n?"
    curl --location --request POST -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        -H 'Content-Type: application/json' \
        https://api.civo.com/v2/kubernetes/clusters \
        --data-raw '{
            "pools":[
            {
                "id": "redash",
                "size": "g4s.kube.medium",
                "count": 1
            }
            ],
            "network_id": "'${NETWORK_ID}'",
            "region": "'${REGION}'",
            "name": "'${APP_NAME}'",
            "instance_firewall": "'${FW_ID}'",
            "firewall_rule": "443;6443"
        }' | yq -r -ojson '.'

    # loop while this is BUILDING
    K8S_READY=`curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
        "https://api.civo.com/v2/kubernetes/clusters?region=LON1" | 
        yq -P -r -o json '.items[] | select(.name == env(appName)) | .ready'`

    while [[ "${K8S_READY}" != "true" ]]; do

        printf "${K8S_READY}, sleeping\n\n"
        sleep 30
        K8S_READY=`export appName=${APP_NAME} && \
            curl -s -H "Authorization: bearer ${CIVO_TOKEN}" \
            "https://api.civo.com/v2/kubernetes/clusters?region=LON1" | 
            yq -P -r -o json '.items[] | select(.name == env(appName)) | .ready'`
    done

    # when done, get the kubeconfig
    ${CIVO_BIN} k8s config ${APP_NAME} --region LON1 > CIVO_${APP_NAME}_KUBECONFIG
fi

