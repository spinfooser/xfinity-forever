#!/bin/sh


function GetLoginFormBody() {
    # Causes redirect to comcast login form
    local OUTPUT=$(curl --max-time 1.0 -s -L "1.1.1.1" 2>&1)
    echo "$OUTPUT"
}

# Argument #1: Output from LoginFormBody request
function GetHashKeypair() {
    local HASH=$(echo "$1" | sed -n -E "s/.*'hash': \"([^\"]*)\",.*/\1/p")
    echo "hash=$HASH"
}

function WasHashKeypairSuccessful() {
    local RESULT=$(echo "$1" | sed -n -E 's/(hash=.+)/\1/p')
    if [ -z "$RESULT" ]; then
        echo "Error"
    else
        echo "Success"
    fi
}

function IsAuthenticated() {
    local temp_file=$(mktemp)
    curl -s -i --max-time 1.0 "1.1.1.1" &>$temp_file
    local CURL_CODE=$?
    local REDIRECT=$(sed -n -E 's/.*Location: .+xfinity.com/\1/p' $temp_file)
    if [ $CURL_CODE -eq 0 ] && [ -z "$REDIRECT" ]; then
        echo "Authenticated"
    elif [ ! $CURL_CODE -eq 0 ]; then
        echo "HttpError"
    else
        echo "Unauthenticated"
    fi
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
    curl --max-time 1.0 -s -S 'https://prov.wifi.xfinity.com/eap_login_prov.php' -H 'Content-Type: application/x-www-form-urlencoded' \
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
        echo "Success"
    else
        echo "Error"
    fi
}

function BuildEAPProfile() {
    local CONFIG_FILE_NAME="$1"
    local OUTPUT=$(curl --max-time 1.0 -sSv -K $CONFIG_FILE_NAME 2>&1)
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
        echo "Success"
    else
        echo "Error"
    fi
}

function MainLoop() {
    while true;
    do
        local SLEEP_AMOUNT=6
        sleep $SLEEP_AMOUNT
        local IS_AUTHENTICATED_RESULT=$(IsAuthenticated)
        if [ $IS_AUTHENTICATED_RESULT == "HttpError" ]; then
            logger xfinityForever "Failed to connect to reach any network address. Result: $IS_AUTHENTICATED_RESULT"
        fi
        if [ $IS_AUTHENTICATED_RESULT == "Unauthenticated" ]; then
            logger xfinityForever "Detected comcast blocking internet!"
            logger xfinityForever "Retreiving hidden form hash..."
            local LOGIN_FORM=$(GetLoginFormBody)
            local LOGIN_FORM_CODE=$?
            if [ ! $LOGIN_FORM_CODE -eq 0 ]; then
                logger xfinityForever "Form curl request failed with error code $LOGIN_FORM_CODE"
                logger xfinityForever "Error response: $LOGIN_FORM"
                continue
            fi

            local HASH_KEYPAIR=$(GetHashKeypair "$LOGIN_FORM")
            local HASH_EXTRACT_RESULT=$(WasHashKeypairSuccessful $HASH_KEYPAIR)
            if [ $HASH_EXTRACT_RESULT == "Error" ]; then
                logger xfinityForever "Failed to extract hash code from login form"
                logger xfinityForever "Hash keypair: $HASH_KEYPAIR"
                continue
            fi

            logger xfinityForever "Submitting login information..."
            local LOGIN_RESULT=$(Login $HASH_KEYPAIR)
            local LOGIN_CODE=$?
            if [ ! $LOGIN_CODE -eq 0 ]; then
                logger xfinityForever "Login curl failed with error code $LOGIN_CODE. Result: $LOGIN_RESULT"
                continue
            fi

            local LOGIN_SUCCESS=$(WasLoginSuccessful "$LOGIN_RESULT")
            if [ $LOGIN_SUCCESS == "Error" ]; then
                logger xfinityForever "Log in to comcast failed...was the username or password typed wrong?"
                logger xfinityForever "Full Login Result: $LOGIN_RESULT"
                continue
            fi

            logger xfinityForever "Log in to EAP succeeded!"
            logger xfinityForever "Building EAP Profile"
            local BUILD_PROFILE_CONFIG_FILE=$(CreateBuildProfileRequestConfig "$LOGIN_RESULT")
            local BUILD_PROFILE_RESULT=$(BuildEAPProfile $BUILD_PROFILE_CONFIG_FILE)
            local BUILD_PROFILE_SUCCESS=$(WasBuildEAPSuccessful "$BUILD_PROFILE_RESULT")
            if [ $BUILD_PROFILE_SUCCESS == "Error" ]; then
                logger xfinityForever "Building EAP profile failed: $BUILD_PROFILE_RESULT"
                continue
            fi

            logger xfinityForever "EAP Profile Built. Internet is back online!"
        fi
    done
}

MainLoop
