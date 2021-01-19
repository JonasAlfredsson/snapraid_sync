#!/bin/bash
################################################################################
#                         Email/Mutt Related Functions                         #
#------------------------------------------------------------------------------#
# This file contains functions which are responsible for assembling and        #
# sending emails with the help of mutt.                                        #
################################################################################

# Adds a HTML header to the supplied file. This will make the text font, in the
# mail, monospaced for neater formatting.
add_mail_header() {
    cat <<EOT >> "${1}"
<html>
<body>
<pre style="font: monospace">
EOT
}

# Adds a HTML footer to the supplied file. This is necessary to "close" the
# stuff introduced in the header.
add_mail_footer() {
    cat <<EOT >> "${1}"
</pre>
</body>
</html>
EOT
}

# Get the line number in a file where you can find "SnapRAID status report:".
get_status_line() {
    local trim_line="$(grep -n 'SnapRAID status report:' "${tmp_file}" | head -n 1 | cut -d: -f1)"
    if [ -z "${trim_line}" ]; then
        trim_line=1
    fi
    echo "${trim_line}"
}

# Add some decoration around the log output if it is included in the mail body.
email_add_short_log() {
    cat <<EOT >> "${mail_body}"
===============BEGIN LOG===============
$(cat "${1}")
================END LOG================
EOT
}

# The main function used for actually sending the mails.
send_mail() {
    if [ -z "${EMAIL_ADDRESS}" ]; then
        warning "No email address defined; cannot send any mails"
    elif [ "${NONINTERACTIVE}" == 'false' ]; then
        info "The 'NONINTERACTIVE' variable is not true; will not send any mails"
    else
        # Assemble the mail with correct header and footer.
        local tmp_mail="$(mktemp)"
        add_mail_header "${tmp_mail}"
        cat "${mail_body}" >> "${tmp_mail}"
        add_mail_footer "${tmp_mail}"

        # If specified, attach the entire log output to the email.
        if [ "${MAIL_ATTACH_LOG}" == "true" ]; then
            info "Sending notification e-mail with attached log file"
            # Send the email.
            ${MAIL_BIN} \
                -s "${EMAIL_SUBJECT_PREFIX} ${1}" \
                -e 'set content_type="text/html"' \
                -a "${LOG_FILE}" -- \
                "${EMAIL_ADDRESS}" < "${tmp_mail}"
            wait
        else
            info "Sending notification e-mail"
            ${MAIL_BIN} \
                -s "${EMAIL_SUBJECT_PREFIX} ${1}" \
                -e 'set content_type="text/html"' \
                "${EMAIL_ADDRESS}" < "${tmp_mail}"
            wait
        fi

        # Empty the "mail_body" file, and remove the temporary file.
        echo -n "" > "${mail_body}"
        rm "${tmp_mail}"
    fi
}

# Send a detailed email explaining why we will not sync.
email_no_sync() {
    cat <<EOT >> "${mail_body}"
Threshold values have been exceeded; will not perform a sync.

$(cat "${tmp_file}" | tail -n 8 | head -n 7)

Delete threshold is ${DELETE_THRESHOLD}
Update threshold is $(if [ "${UPDATE_THRESHOLD}" -eq "-1" ]; then echo "disabled"; else echo "${UPDATE_THRESHOLD}"; fi)
EOT
    send_mail "WARNING"
}

# Send a warning email notifying the user that something went wrong during
# either syncing or scrubbing.
email_no_ok() {
    cat <<EOT >> "${mail_body}"
${1}
Aborting any further execution.

=============LAST $(( ${nbr_content_files} * 2 + 6 )) LINES=============
$( cat "${LOG_FILE}" | tail -n $(( ${nbr_content_files} * 2 + 3 )) )
================END LOG================

$( cat "${tmp_file}" | tail -n +$(get_status_line) )
EOT
    send_mail "WARNING"
}

# Send a mail stating that everything went fine and attach some extra status
# information.
email_ok() {
    cat <<EOT >> "${mail_body}"
$( cat "${tmp_file}" | tail -n +$(get_status_line) )
EOT
    send_mail "OK"
}
