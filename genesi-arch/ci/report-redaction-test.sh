#!/usr/bin/env bash
#
# report-redaction-test.sh — genesi-report must not leak the reporter.
#
# The tool's whole purpose is to get a user's machine details in front of a
# maintainer, and the file it produces is meant to be attached to a PUBLIC issue.
# So its redaction is not a nice-to-have wrapped around the useful part — it IS
# the part that decides whether the tool is safe to ship. A bug reporter that
# leaks its reporter is worse than none: it teaches people not to use it, and it
# does the damage before anyone reads the output.
#
# That property cannot be checked by reading the script, because the failure is
# always a pattern nobody thought of. So it is checked here, against real
# strings, and the list only ever grows.
#
# Usage: genesi-arch/ci/report-redaction-test.sh
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="${ROOT}/genesi-arch/packages/genesi-report/genesi-report"
[ -f "${SRC}" ] || { echo "missing ${SRC}"; exit 1; }

# The real function, pulled out of the shipped script. A copy here would pass
# forever while the tool drifted away from it.
eval "$(sed -n '/^redact() {/,/^}/p' "${SRC}")"
type redact >/dev/null 2>&1 || { echo "could not extract redact() from ${SRC}"; exit 1; }

# Stand-ins for whoever is running it.
REAL_USER="matheus"
REAL_HOST="alan-segundo"

fails=0

leaks() { # <name> <input> <secret that must NOT survive>
    local out
    out="$(printf '%s\n' "$2" | redact)"
    if printf '%s' "${out}" | grep -qF -- "$3"; then
        printf '  FAIL  %s\n        leaked: %s\n        out:    %s\n' "$1" "$3" "${out}"
        fails=$((fails + 1))
    else
        printf '  PASS  %s\n' "$1"
    fi
}

keeps() { # <name> <input> <detail that MUST survive>
    local out
    out="$(printf '%s\n' "$2" | redact)"
    if printf '%s' "${out}" | grep -qF -- "$3"; then
        printf '  PASS  %s\n' "$1"
    else
        printf '  FAIL  %s\n        lost: %s\n        out:  %s\n' "$1" "$3" "${out}"
        fails=$((fails + 1))
    fi
}

echo "== genesi-report redaction =="
echo
echo "-- what must never survive --"

leaks "username in a path"      "/home/matheus/Documents/taxes.pdf"      "matheus"
leaks "username on its own"     "user matheus logged in"                 "matheus"
leaks "hostname"                "alan-segundo kernel: oops"              "alan-segundo"
leaks "IPv4"                    "connected to 192.168.1.47 port 8080"    "192.168.1.47"
leaks "public IPv4"             "curl failed to 203.0.113.9"             "203.0.113.9"
leaks "MAC address"             "wlan0: link up, aa:bb:cc:dd:ee:ff"      "aa:bb:cc:dd:ee:ff"
leaks "email"                   "git author matheusv090807@gmail.com"    "matheusv090807@gmail.com"
leaks "Wi-Fi name"              'wpa_supplicant: SSID="Casa do Matheus"' "Casa do Matheus"
leaks "serial number"           "Serial Number: 5CD9218XYZ"              "5CD9218XYZ"

echo
echo "-- what must survive, or the report is useless --"

keeps "kernel version"          "Kernel: 6.12.4-2-cachyos"               "6.12.4-2-cachyos"
keeps "package name + version"  "genesi-ai-mode 1.0.0-189"               "genesi-ai-mode 1.0.0-189"
keeps "the failing unit"        "genesi-automationd.service failed"      "genesi-automationd.service"
keeps "GPU model"               "NVIDIA GA107 [GeForce RTX 3050]"        "GeForce RTX 3050"
keeps "the loaded driver"       "  nouveau"                              "nouveau"
keeps "an actual error"         "error: unable to satisfy dependency"    "unable to satisfy dependency"
keeps "a device path"           "Mounting /dev/loop0 on /run/archiso"    "/dev/loop0"

echo
echo "-- the shape of the tool itself --"

# These are behavioural promises the help text makes to the user. If any of them
# stops being true the tool becomes something the user did not agree to run.
check_src() { # <name> <grep pattern>
    if grep -q "$2" "${SRC}"; then printf '  PASS  %s\n' "$1"
    else printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); fi
}
if grep -nE '(curl|wget)[^|]*(-X *POST|--data|--upload-file|-F )' "${SRC}" >/dev/null 2>&1; then
    printf '  FAIL  the tool contains an upload — it must never send anything itself\n'
    fails=$((fails + 1))
else
    printf '  PASS  the tool contains no upload path\n'
fi
check_src "the report file is written with a private umask" 'umask 077'
check_src "the browser step asks first"                     'Open the pre-filled issue form'
check_src "the journal is limited to this boot"             'journalctl -b -p err'

echo
if [ "${fails}" -eq 0 ]; then echo "report redaction: OK"; exit 0; fi
echo "report redaction: ${fails} failure(s)"
exit 1
