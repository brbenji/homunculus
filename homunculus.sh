#!/bin/bash

SHIP="zod"
CODE="lidlut-tabwed-pillex-ridrup"
BASE_URL="localhost:8081"

auth_res=$(curl -i -X POST --silent -d "password=$CODE" "$BASE_URL/~/login")
cookie_header="$(echo "$auth_res" | grep -i 'set-cookie:' | awk '{print $2}' | sed 's/.$//')"
channel_id="$(date +'%Y%m%d')$RANDOM"
message_id=0
sub_id=0
stop_flag=false

start_connection() {
    send_size
    ((message_id++))
    sub_id=$message_id
    curl -X PUT \
         --cookie "$cookie_header" \
         -d "[{
             \"id\":$message_id,
             \"action\":\"subscribe\",
             \"ship\":\"$SHIP\",
             \"app\":\"homunculus\",
             \"path\":\"/homunculus-http\"
             }]" \
         "$BASE_URL/~/channel/$channel_id" \
    > /dev/null 2>&1
}

end_connection() {
    ((message_id++))
    curl -X PUT \
         --cookie "$cookie_header" \
         -d "[{
             \"id\":$message_id,
             \"action\":\"unsubscribe\"
             \"subscription\":$sub_id
             }]" \
         "$BASE_URL/~/channel/$channel_id" \
    > /dev/null 2>&1
    ((message_id++))
    curl -X PUT \
         --cookie "$cookie_header" \
         -d "[{
             \"id\":$message_id,
             \"action\":\"delete\"
             }]" \
         "$BASE_URL/~/channel/$channel_id" \
    > /dev/null 2>&1
    stop_flag=true
}

poke() {
    ((message_id++))
    curl -X PUT \
         --cookie "$cookie_header" \
         -d "[{
             \"id\":$message_id,
             \"action\":\"poke\",
             \"ship\":\"$SHIP\",
             \"app\":\"homunculus\",
             \"mark\":\"json\",
             \"json\":$1
             }]" \
         "$BASE_URL/~/channel/$channel_id" \
    > /dev/null 2>&1
}

ack() {
    ((message_id++))
    curl -X PUT \
         --cookie "$cookie_header" \
         -d "[{
             \"id\":$message_id,
             \"action\":\"ack\",
             \"event-id\":$1
             }]" \
         "$BASE_URL/~/channel/$channel_id" \
    > /dev/null 2>&1
}

stream() {
    local event_id=0
    curl -N --silent \
         -H "Accept:text/event-stream" \
         --cookie "$cookie_header" \
         "$BASE_URL/~/channel/$channel_id" |
    while read -r -s line; do
        if [[ "${line:0:4}" = "id: " ]]; then
            event_id="${line:4}"
        elif [[ "${line:0:6}" = "data: " ]] &&  grep -q "json" <<< "$line"; then
            dat=$(echo "${line:6}" | jq -r '.json')
            dat=${dat//%/%%}
            printf "$dat"
            ack $event_id
        fi
    done
}

read_input() {
    while read -r -s -N 1 char; do
        if $stop_flag; then
            break
        elif [[ "$char" = $'\033' ]] || [[ "$char" =~ [[:cntrl:]] ]]; then
            read -r -s -t 0.001 chars
            printf -v seq "%q" "$char$chars"
            if [[ "${seq:0:1}" = '$' ]]; then
                eval sequence=${seq:1}
            else
                eval sequence=$seq
            fi
            poke "\"\\$sequence\""
        elif [[ "$char" = '\' ]] || [[ "$char" = '"' ]]; then
            poke "\"\\$char\""
        else
            poke "\"$char\""
        fi
    done
}

send_size() {
    cols=$(tput cols)
    rows=$(tput lines)
    poke "[$cols, $rows]"
}

PS1=
stty -echo
printf "\e[?1000;1006;1015h"

start_connection

stream &

trap "end_connection" INT

read_input

clear
stty echo
printf "\e[?1000;1006;1015l"
