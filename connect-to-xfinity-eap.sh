#!/bin/sh

function FindGateway() {
    local GATEWAY_IP=$(ip route | grep default | sed -n -E 's/.*via ([0-9]+.[0-9]+.[0-9]+.[0-9]+).*/\1/p')
    echo "$GATEWAY_IP"
}

function GetHashKeypair() {
    local GATEWAY=$(FindGateway)
    local temp_file=$(mktemp)
    curl -s -L "$GATEWAY" &>$temp_file
    local HASH=$(sed -n -E 's/.*<input.*name="hash".*value="([^"]*)".*\/>.*/\1/p' $temp_file)
    echo "hash=$HASH"
    rm ${temp_file} > /dev/null
}

function GetUserKeypair() {
    local USER="$(cat /etc/config/wireless | sed -n -E "s/.*option identity '(.*)@.*/\1/p")"
    echo "username=$USER"
}

function GetPasswordKeypair() {
    local PASSWORD="$(cat /etc/config/wireless | sed -n -E "s/.*option password '(.*)'.*/\1/p")"
    echo "password=$PASSWORD"
}

function Login() {
    local HASH_KEY_PAIR=$1
    curl -s -S 'https://prov.wifi.xfinity.com/eap_login_prov.php' -H 'Content-Type: application/x-www-form-urlencoded' \
        -H 'Origin: https://prov.wifi.xfinity.com' \
        -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/71.0.3578.98 Safari/537.36' \
        --data-urlencode "$(GetUserKeypair)" \
        --data-urlencode "$(GetPasswordKeypair)" \
        --data-urlencode "$HASH_KEY_PAIR" \
        --data-urlencode 'friendlyname=' \
        --data-urlencode 'javascript=false' \
        --data-urlencode 'method=authenticate' \
        -i
}

function WasLoginSuccessful() {
    local REDIRECT=$(echo $1 | sed -n -E 's/.*Location: https:\/\/prov.wifi.xfinity.com\/index.php?prov_type=eap.*/\1/p')
    if [ -z "$REDIRECT" ]
    then
        echo "1"
    else
        echo "0"
    fi
}

function BuildEAPProfile() {
    local CONFIG_FILE_NAME="$1"
    local OUTPUT=$(curl -sSv -K $CONFIG_FILE_NAME 2>&1)
    rm ${CONFIG_FILE_NAME} > /dev/null
    echo "$OUTPUT"
}

# Argument #1: Login Curl Result containing Location Header Value
function CreateBuildProfileRequestConfig() {
    local LOGIN_RESULT_ARG=$1
    local CONFIG_FILE_NAME=$(mktemp)
    printf "url = https://prov.wifi.xfinity.com/prov/build_profile_eap.php?hash=" >> $CONFIG_FILE_NAME
    local BUILD_PROFILE_HASH=$(echo $LOGIN_RESULT_ARG | sed -n -E 's/.*https:\/\/prov.wifi.xfinity.com\/prov\/secure_eap_page.php\?hash=([^ ]*) .*/\1/p' >> $CONFIG_FILE_NAME)
    echo $CONFIG_FILE_NAME
}

function WasBuildEAPSuccessful() {
    local REDIRECT=$(echo $1 | sed -n -E 's/.*Location: http:\/\/wifi.xfinity.com\/.*/\1/p')
    if [ -z "$REDIRECT" ] && [ ! -z "$1" ]
    then
        echo "1"
    else
        echo "0"
    fi
}

function MainLoop() {
    while true;
    do
        local SLEEP_AMOUNT=5
        sleep $SLEEP_AMOUNT
        timeout --preserve-status 0.15 ping -c1 www.google.com &>/dev/null
        local INTERNET_UP=$?
        timeout --preserve-status 0.15 ping -c1 10.224.0.1 &>/dev/null
        local COMCAST_GATEWAY_UP=$?
        if [ ! $INTERNET_UP -eq 0 ] && [ $COMCAST_GATEWAY_UP -eq 0 ]
        then
            logger xfinityForever "Detected comcast blocking internet!"
            logger xfinityForever "Logging in using credentials..."
            local HASH_KEYPAIR="$(GetHashKeypair)"
            local LOGIN_RESULT=$(Login $HASH_KEYPAIR)
            local LOGIN_SUCCESS=$(WasLoginSuccessful $LOGIN_RESULT)
            if [ $LOGIN_SUCCESS == "1" ]
            then
                logger xfinityForever "Log in to EAP succeeded!"
                logger xfinityForever "Building EAP Profile"
                local BUILD_PROFILE_CONFIG_FILE=$(CreateBuildProfileRequestConfig "$LOGIN_RESULT")
                local BUILD_PROFILE_RESULT=$(BuildEAPProfile $BUILD_PROFILE_CONFIG_FILE)
                local BUILD_PROFILE_SUCCESS=$(WasBuildEAPSuccessful $BUILD_PROFILE_RESULT)
                if [ $BUILD_PROFILE_SUCCESS == "1" ]
                then
                    logger xfinityForever "EAP Profile Built. Internet is back online!"
                else
                    logger xfinityForever "Building EAP profile failed...here is the output"
                    logger xfinityForever "$BUILD_PROFILE_RESULT"
                fi
            else
                logger xfinityForever "Log in to comcast failed...was the username or password typed wrong?"
                logger xfinityForever "Full Login Result: $LOGIN_RESULT"
            fi
        fi;
    done
}

MainLoop
