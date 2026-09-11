#!/usr/bin/env bash
#
# Live round trip for the apigw-sqs module.
#
# Stands the module up in whatever account the environment points at, POSTs
# every payload under payloads/, reads each one back off the queue, and asserts
# the delivered body is byte-identical to what was sent. Tears the stack down on
# the way out, including on failure and on interrupt.
#
# This is the only test that proves the integration request template
# URL-encodes the message body. The offline suite can assert that the template
# says $util.urlEncode, but VTL is evaluated by API Gateway and nothing offline
# renders it.
#
# Usage:
#   AWS_PROFILE=... AWS_REGION=... ./run.bash
#
# Requires: terraform, aws, jq, curl, cmp.

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly SCRIPT_DIR
readonly PAYLOAD_DIR="${SCRIPT_DIR}/payloads"

## SQS refuses to reuse a deleted queue's name for 60 seconds, so every run gets
## its own names rather than making a re-run wait.
NAME_PREFIX="apigwsqs-test-$(date -u +%Y%m%d%H%M%S)"
readonly NAME_PREFIX

## A newly created usage plan key is not visible to every API Gateway host at
## once. Until it is, an otherwise valid request is answered 403 with
## "No Usage Plan found for key and API Stage" in the execution log, and the
## rejections interleave with successes rather than forming a clean
## before/after. One 200 therefore proves nothing about the next request, so
## every POST retries, not just the readiness probe.
##
## The budgets are sized from an observed run, not guessed: sixteen minutes
## after apply, a stack was still answering only about one request in five.
## Ten minutes to the first 200 and five minutes per payload is therefore the
## floor for this to be a test of encoding rather than a test of propagation.
readonly POST_MAX_ATTEMPTS=100
readonly POST_RETRY_SLEEP=3

readonly READY_MAX_ATTEMPTS=120
readonly READY_RETRY_SLEEP=5

WORK_DIR=""
APPLIED=0
PAYLOADS_TOTAL=0
PAYLOADS_RUN=0
PAYLOADS_PASSED=0

if [ -t 2 ]; then
    readonly C_RESET=$'\033[0m'
    readonly C_DIM=$'\033[2m'
    readonly C_BOLD=$'\033[1m'
    readonly C_RED=$'\033[31m'
    readonly C_GREEN=$'\033[32m'
    readonly C_YELLOW=$'\033[33m'
    readonly C_BLUE=$'\033[34m'
else
    readonly C_RESET="" C_DIM="" C_BOLD="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
fi

function echo_stderr() {
    echo "${*}" >&2
}

function log_at() {
    local -r colour="${1}"
    local -r label="${2}"
    shift 2
    printf '%s%s%s %s%-5s%s %s\n' \
        "${C_DIM}" "$(date -u +%H:%M:%S)" "${C_RESET}" \
        "${colour}" "${label}" "${C_RESET}" \
        "${*}" >&2
}

function log_info() {
    log_at "${C_BLUE}" "info" "${@}"
}

function log_ok() {
    log_at "${C_GREEN}" "ok" "${@}"
}

function log_warn() {
    log_at "${C_YELLOW}" "warn" "${@}"
}

function log_error() {
    log_at "${C_RED}" "error" "${@}"
}

## Phase banners exist because the slow steps are the opaque ones: without a
## marker, a two-minute terraform apply is indistinguishable from a hang.
function log_phase() {
    printf '\n%s=== %s %s(%ss elapsed)%s\n' \
        "${C_BOLD}" "${*}" "${C_DIM}" "${SECONDS}" "${C_RESET}" >&2
}

function fail() {
    log_error "${*}"
    exit 1
}

## Indents a subprocess's own output so it reads as subordinate to the phase
## banner above it rather than as this script's own logging.
function indent_stream() {
    local line
    while IFS= read -r line; do
        printf '    %s%s%s\n' "${C_DIM}" "${line}" "${C_RESET}" >&2
    done
}

## Runs terraform with its output visible. Terraform disables its own colour
## when it detects the pipe, so the indented stream stays clean.
function run_terraform() {
    local -r action="${1}"
    shift

    log_info "terraform ${action}"

    ## pipefail makes the pipeline carry terraform's status, not the indenter's.
    if ! terraform -chdir="${SCRIPT_DIR}" "${action}" "${@}" 2>&1 | indent_stream; then
        return 1
    fi
}

function is_cmd_available() {
    command -v "${1}" >/dev/null 2>&1
}

## Reports every missing dependency in one pass, so a bare machine does not
## surface them one run at a time.
function check_dependencies() {
    local cmd
    local -a missing=()

    for cmd in terraform aws jq curl cmp; do
        is_cmd_available "${cmd}" || missing+=("${cmd}")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        fail "not on PATH: ${missing[*]}"
    fi

    ## cmp --silent and date -u are the GNU spellings this script relies on;
    ## macOS ships BSD versions that accept both, but a trimmed container may
    ## not have cmp at all, which the loop above catches.
    log_info "dependencies present: terraform, aws, jq, curl, cmp"
}

function on_signal() {
    local -r signal="${1}"
    echo_stderr ""
    log_warn "caught ${signal}, tearing down before exit"
    ## 128 + signal number, so the caller can tell an interrupt from a test
    ## failure. Exiting here runs the EXIT trap, which is what destroys.
    case "${signal}" in
    INT) exit 130 ;;
    TERM) exit 143 ;;
    *) exit 1 ;;
    esac
}

function cleanup() {
    local -r exit_code="${?}"

    if [ "${APPLIED}" -eq 1 ]; then
        log_phase "destroying ${NAME_PREFIX}"
        if ! run_terraform destroy \
            -auto-approve \
            -input=false \
            -var "name_prefix=${NAME_PREFIX}"; then
            log_warn "destroy failed, ${NAME_PREFIX} may still exist in the account"
            log_warn "re-run: terraform -chdir=\"${SCRIPT_DIR}\" destroy -var name_prefix=${NAME_PREFIX}"
        else
            log_ok "destroyed ${NAME_PREFIX}"
        fi
    fi

    if [ -n "${WORK_DIR}" ] && [ -d "${WORK_DIR}" ]; then
        rm -rf "${WORK_DIR}"
    fi

    return "${exit_code}"
}

## API Gateway answers 403 for a while after a deployment, before the stage has
## propagated. Without this a fresh stack fails on the first payload for reasons
## that have nothing to do with encoding.
function wait_for_api() {
    local -r url="${1}"
    local -r key="${2}"
    local attempt code

    log_info "probing ${url}"

    for attempt in $(seq 1 "${READY_MAX_ATTEMPTS}"); do
        code="$(curl \
            --silent \
            --output /dev/null \
            --write-out '%{http_code}' \
            --header 'Content-Type: application/json' \
            --header "x-api-key: ${key}" \
            --data-raw '{"case":"readiness-probe"}' \
            --request POST \
            "${url}" || true)"

        if [ "${code}" = "200" ]; then
            log_ok "api answered 200 after ${attempt} probe(s)"
            return 0
        fi

        ## Chatty for the first few, then every sixth, so a ten-minute wait does
        ## not bury the run in a hundred identical lines while still proving it
        ## is alive.
        if ((attempt <= 3 || attempt % 6 == 0)); then
            log_info "probe ${attempt}/${READY_MAX_ATTEMPTS} got ${code}, still waiting (${SECONDS}s elapsed)"
        fi

        sleep "${READY_RETRY_SLEEP}"
    done

    fail "api did not become ready (last status: ${code})"
}

## Posts one file, retrying only the 403 that the usage plan propagation causes.
## Any other status returns immediately, so a real failure is not slept over.
## Echoes the final status code.
function post_with_retry() {
    local -r body_file="${1}"
    local -r url="${2}"
    local -r key="${3}"
    local attempt code

    for attempt in $(seq 1 "${POST_MAX_ATTEMPTS}"); do
        code="$(curl \
            --silent \
            --output /dev/null \
            --write-out '%{http_code}' \
            --header 'Content-Type: application/json' \
            --header "x-api-key: ${key}" \
            --data-binary "@${body_file}" \
            --request POST \
            "${url}" || true)"

        if [ "${code}" = "200" ]; then
            if ((attempt > 1)); then
                log_info "usage plan visible after ${attempt} attempt(s)"
            fi
            break
        fi

        [ "${code}" != "403" ] && break

        if ((attempt <= 2 || attempt % 10 == 0)); then
            log_info "attempt ${attempt}/${POST_MAX_ATTEMPTS} got 403, usage plan still propagating"
        fi

        sleep "${POST_RETRY_SLEEP}"
    done

    printf '%s' "${code}"
}

## Reads and deletes everything currently on the queue, so a readiness probe or
## a leftover from an aborted run cannot be mistaken for a payload.
##
## Called before every payload, not once at startup: the assertion reads
## whichever message happens to be next, so a single stray message would
## otherwise shift every subsequent payload against the wrong body and report a
## cascade of encoding failures that are really one contaminated queue.
function drain_queue() {
    local -r queue_url="${1}"
    local -r quiet="${2:-}"
    local response handle batch
    local drained=0

    while true; do
        if ! response="$(aws sqs receive-message \
            --queue-url "${queue_url}" \
            --max-number-of-messages 10 \
            --wait-time-seconds 1 \
            --output json)"; then
            fail "could not read from ${queue_url}"
        fi

        [ -z "${response}" ] && break

        ## A read loop over process substitution rather than mapfile, which does
        ## not exist in the bash 3.2 that `env bash` still finds on stock macOS.
        batch=0
        while IFS= read -r handle; do
            [ -z "${handle}" ] && continue
            aws sqs delete-message \
                --queue-url "${queue_url}" \
                --receipt-handle "${handle}" >/dev/null
            batch=$((batch + 1))
        done < <(printf '%s' "${response}" | jq -r '.Messages[]?.ReceiptHandle')

        [ "${batch}" -eq 0 ] && break
        drained=$((drained + batch))
    done

    if [ -n "${quiet}" ]; then
        ## Per-payload drains are silent unless they actually found something,
        ## which is the case worth seeing.
        if [ "${drained}" -gt 0 ]; then
            log_warn "discarded ${drained} unexpected message(s) before posting"
        fi
        return 0
    fi

    log_ok "queue drained (${drained} stale message(s) removed)"
}

## Posts one payload and asserts the queue hands back exactly those bytes.
function check_payload() {
    local -r payload_file="${1}"
    local -r url="${2}"
    local -r key="${3}"
    local -r queue_url="${4}"
    local -r index="${5}"
    local name sent received response handle code started

    name="$(basename "${payload_file}")"
    started="${SECONDS}"
    sent="${WORK_DIR}/sent"
    received="${WORK_DIR}/received"

    log_info "[${index}/${PAYLOADS_TOTAL}] ${name} ($(wc -c <"${payload_file}" | tr -d ' ') bytes)"

    ## Guarantees the message read back below is the one posted here, rather
    ## than whatever a previous step or an unrelated client left behind.
    drain_queue "${queue_url}" quiet

    ## Trailing newlines are stripped so the corpus can stay POSIX text files
    ## while the comparison still runs over exactly the bytes that were sent.
    printf '%s' "$(cat "${payload_file}")" >"${sent}"

    code="$(post_with_retry "${sent}" "${url}" "${key}")"
    if [ "${code}" != "200" ]; then
        log_error "[${index}/${PAYLOADS_TOTAL}] ${name}: POST returned ${code}"
        return 1
    fi

    if ! response="$(aws sqs receive-message \
        --queue-url "${queue_url}" \
        --max-number-of-messages 1 \
        --wait-time-seconds 20 \
        --output json)"; then
        log_error "[${index}/${PAYLOADS_TOTAL}] ${name}: receive-message failed"
        return 1
    fi

    if [ -z "${response}" ] || ! printf '%s' "${response}" | jq -e '.Messages[0]' >/dev/null; then
        log_error "[${index}/${PAYLOADS_TOTAL}] ${name}: nothing arrived on the queue"
        return 1
    fi

    ## -j so jq adds no trailing newline of its own; the comparison has to be
    ## over the exact bytes.
    printf '%s' "${response}" | jq -rj '.Messages[0].Body' >"${received}"

    handle="$(printf '%s' "${response}" | jq -r '.Messages[0].ReceiptHandle')"
    aws sqs delete-message --queue-url "${queue_url}" --receipt-handle "${handle}" >/dev/null

    ## cmp on raw bytes, deliberately not a jq-level comparison: a JSON compare
    ## would hide exactly the escaping and truncation a form-encoding bug causes.
    if ! cmp --silent "${sent}" "${received}"; then
        log_error "[${index}/${PAYLOADS_TOTAL}] ${name}: delivered body differs from what was sent"
        log_error "  sent     ($(wc -c <"${sent}" | tr -d ' ') bytes): $(head -c 200 "${sent}")"
        log_error "  received ($(wc -c <"${received}" | tr -d ' ') bytes): $(head -c 200 "${received}")"
        return 1
    fi

    log_ok "[${index}/${PAYLOADS_TOTAL}] ${name} delivered byte-identically ($((SECONDS - started))s)"
    return 0
}

function main() {
    log_phase "preflight"
    check_dependencies

    [ -d "${PAYLOAD_DIR}" ] || fail "no payloads directory at ${PAYLOAD_DIR}"

    WORK_DIR="$(mktemp -d)"
    trap cleanup EXIT
    trap 'on_signal INT' INT
    trap 'on_signal TERM' TERM

    log_info "region ${AWS_REGION:-${AWS_DEFAULT_REGION:-unset}}, profile ${AWS_PROFILE:-default}"
    log_info "stack name prefix ${NAME_PREFIX}"

    log_phase "terraform init"
    run_terraform init -input=false || fail "terraform init failed"

    log_phase "terraform apply"
    ## Set before the call, not after: an apply that fails partway through has
    ## still created resources that need destroying.
    APPLIED=1
    run_terraform apply \
        -auto-approve \
        -input=false \
        -var "name_prefix=${NAME_PREFIX}" ||
        fail "terraform apply failed"

    local url key queue_url
    url="$(terraform -chdir="${SCRIPT_DIR}" output -raw api_url)" || fail "could not read api_url"
    key="$(terraform -chdir="${SCRIPT_DIR}" output -raw api_key)" || fail "could not read api_key"
    queue_url="$(terraform -chdir="${SCRIPT_DIR}" output -raw queue_url)" || fail "could not read queue_url"

    log_ok "api  ${url}"
    log_ok "queue ${queue_url}"

    log_phase "waiting for the api"
    wait_for_api "${url}" "${key}"

    log_phase "draining the queue"
    drain_queue "${queue_url}"

    local -a payloads=()
    local payload_file
    for payload_file in "${PAYLOAD_DIR}"/*.json; do
        payloads+=("${payload_file}")
    done
    PAYLOADS_TOTAL="${#payloads[@]}"
    [ "${PAYLOADS_TOTAL}" -gt 0 ] || fail "no payloads found in ${PAYLOAD_DIR}"

    log_phase "posting ${PAYLOADS_TOTAL} payload(s)"

    local -a failed=()
    local index=0
    for payload_file in "${payloads[@]}"; do
        index=$((index + 1))
        PAYLOADS_RUN=$((PAYLOADS_RUN + 1))
        if check_payload "${payload_file}" "${url}" "${key}" "${queue_url}" "${index}"; then
            PAYLOADS_PASSED=$((PAYLOADS_PASSED + 1))
        else
            failed+=("$(basename "${payload_file}")")
        fi
    done

    log_phase "summary"
    ## Reports how far the loop actually got, not just its verdict: a run cut
    ## short leaves the untried payloads unaccounted for otherwise.
    log_info "attempted ${PAYLOADS_RUN} of ${PAYLOADS_TOTAL} payload(s), ${PAYLOADS_PASSED} passed"

    if [ "${#failed[@]}" -gt 0 ]; then
        local name
        for name in "${failed[@]}"; do
            log_error "failed: ${name}"
        done
        log_error "${#failed[@]} of ${PAYLOADS_TOTAL} payload(s) were not delivered byte-identically"
        return 1
    fi

    log_ok "all ${PAYLOADS_TOTAL} payload(s) delivered byte-identically"
    return 0
}

if [[ "${BASH_SOURCE[0]:-${0}}" == "${0}" ]]; then
    main "${@}"
fi
