#!/usr/bin/env bash
#
# run multiple scenarios and report which ones succeeded or failed and print
# the last 3 lines (excluding cleanup logs) for each failed scenario
#
# logs for each scenario are saved to logs/<scenario>.(ok|ko).log
# - the "ok" or "ko" part depents on the success or failure of the scenario
# - existing logs are deleted at the beginning
#
# examples:
# - scenarios 0 1
#
# run demo.sh with the "-l" option for a list of available scenarios

_tit() {
    printf "\n\n\n-------=[ %s ]=-------\n" "$1"
}

scenarios=$*
if [ -z "$scenarios" ]; then
    echo "please provide a list of scenarios to run"
    exit 1
fi

echo -e "running scenarios: $scenarios"
sleep 3

rm -r logs/
mkdir -p logs/

SCENARIOS_OK=()
SCENARIOS_KO=()

# set pipelines to return the last non-zero exit code (0 if all successful)
# required to prevent piping into tee from resetting the exit code to 0
set -o pipefail

for S in $scenarios; do
    _tit "running scenario $S"
    if ./demo.sh -s "$S" 2>&1 | tee "logs/$S.log"; then
        SCENARIOS_OK+=("$S")
        mv "logs/$S.log" "logs/$S.ok.log"
    else
        SCENARIOS_KO+=("$S")
        mv "logs/$S.log" "logs/$S.ko.log"
    fi
        
done

_tit "results"
echo
[ "${#SCENARIOS_OK[*]}" -gt 0 ] && echo "success scenarios: ${SCENARIOS_OK[*]}"
[ "${#SCENARIOS_KO[*]}" -gt 0 ] && echo "failed  scenarios: ${SCENARIOS_KO[*]}"

if ls logs/*.ko.log >/dev/null 2>&1; then
    sleep 3
    _tit "errors from failed scenarios"
    echo
    cat logs/*.ko.log |sed '/stopping services and cleaning/,$d' |tail -n3
fi
