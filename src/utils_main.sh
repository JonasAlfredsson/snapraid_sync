#!/bin/bash
################################################################################
#                          Various Utility Functions                           #
#------------------------------------------------------------------------------#
# These functions are used throughout this entire script, and are mostly       #
# related to managing user input and script output.                            #
################################################################################

# Helper functions used for printing messages to stdout and a log file.
log() {
    echo "$(date +%Y-%m-%dT%H:%M:%S%z) ${1} - ${2}" | tee -a "${LOG_FILE}"
}
info() {
    log "[INFO   ]" "${1}"
}
warning() {
    log "[WARNING]" "${1}"
}
error() {
    log "[ERROR  ]" "${1}"
}

# Some temporary files we can use for storing output.
tmp_file="$(mktemp)"
mail_body="$(mktemp)"

# Helper function to print an exit message and clean up after us on every exit.
clean_exit() {
    info "Exiting script $(basename ${0})"
    rm "${tmp_file}"
    rm "${mail_body}"
}

# Make bash listen to the SIGTERM and SIGINT kill signals, and make them trigger
# a normal "exit" command in this script. Then we tell bash to execute the
# "clean_exit" function, seen above, in the case an "exit" command is triggered.
trap "exit" TERM INT
trap "clean_exit" EXIT

# Go through all input arguments, which may or may not have been provided when
# invoking this script, and change the environment variables accordingly.
check_input_arguments() {
    for var in "$@"
    do
        case "${var,,}" in
            "force")
                info "The 'force' argument has been supplied; will force sync"
                FORCE_SYNC="true"
                ;;
            "scrub")
                info "The 'scrub' argument has been supplied; will scrub after the sync"
                RUN_SCRUB="true"
                ;;
            "noninteractive")
                info "The 'noninteractive' argument has been supplied; will not prompt for user input but will send mail"
                NONINTERACTIVE="true"
                ;;
            *)
                error "Unknown input argument '${var}'"
                exit 1
                ;;
        esac
    done
}
