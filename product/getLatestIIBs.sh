#!/bin/bash
#
# Copyright (c) 2018-2022 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# script to query latest IIBs (one per OCP version) for a given version of DS, Dev Spaces, DevWorkspace, or Web Terminal operators

usage () {
	echo "
Usage: 
  $0 -v PROD_VERSION [OPTIONS]

Options:
  -o OCP_VERSION          To limit results to a single OCP version, use this flag
  -p PROD_NAME        Defaults to 'Dev Spaces'; label on output when multiple OCP versions specified
  -i IMAGE_PREFIX     Defaults to 'devspaces'; used in registry-proxy.engineering.redhat.com/rh-osbs/IMAGE_PREFIX to filter results
                      For example, to check if specific bundle exists in the index, use 'bundle:3.1-123'
  -c 'csv1 csv2 ...'  Defaults to 'operator-bundle'; used to filter results

  --ds                Sets PROD_NAME to 'Dev Spaces' and IMAGE_PREFIX to 'devspaces' (default behaviour)
  --crw               Sets PROD_NAME to 'CodeReady Workspaces' and IMAGE_PREFIX to 'codeready-workspaces'
  --dwo               Sets PROD_NAME to 'DevWorkspace Operator' and IMAGE_PREFIX to 'devworkspace'
  --wto               Sets PROD_NAME to 'Web Terminal Operator' and IMAGE_PREFIX to 'web-terminal'

  --verbose                  Verbose output: include additional information about what's happening
  -q, -qi             Quiet Index  output: instead of default tabbed table with operator bundle, IIB URL + OCP version; show IIB URL only
  -qb                 Quiet Bundle output: instead of default tabbed table with operator bundle, IIB URL + OCP version; show bundle only
"
}

runCommandWithTimeout() {
  this_timeout=$1
  count=1
  (( timeout_intervals=this_timeout/5 ))
  while [[ $count -le $timeout_intervals ]]; do # echo $count
    set +e
    if [[ $VERBOSE -eq 1 ]]; then
      echo; echo "Checking for latest IIBs for $PROD_NAME (${IMAGE_PREFIX}) ${PROD_VERSION} ${csv}  ... [$count/$timeout_intervals]"; echo
    fi
    lastcsv=$(curl -sSLk "https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.index.built&delta=1728000&rows_per_page=30&contains=${IMAGE_PREFIX}" | \
    jq ".raw_messages[].msg.index | .added_bundle_images[0]" -r | sort -uV | grep "${csv}:${PROD_VERSION}" | tail -1 | \
    sed -r -e "s#registry-proxy.engineering.redhat.com/rh-osbs/${IMAGE_PREFIX}-##");

    if [[ "${lastcsv}" ]]; then
      if [[ $OCP_VERSION == "" ]]; then
        line="$(curl -sSLk "https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.index.built&delta=1728000&rows_per_page=30&contains=${IMAGE_PREFIX}" | \
            jq ".raw_messages[].msg.index | [.added_bundle_images[0], .index_image, .ocp_version] | @tsv" -r | sort -uV | \
            grep "${lastcsv}" | sed -r -e "s#registry-proxy.engineering.redhat.com/rh-osbs/${IMAGE_PREFIX}-#  #")"
      else
        line="$(curl -sSLk "https://datagrepper.engineering.redhat.com/raw?topic=/topic/VirtualTopic.eng.ci.redhat-container-image.index.built&delta=1728000&rows_per_page=30&contains=${IMAGE_PREFIX}" | \
          jq ".raw_messages[].msg.index | [.added_bundle_images[0], .index_image, .ocp_version] | @tsv" -r | sort -uV | \
          grep "${lastcsv}" | grep "v${OCP_VERSION}")"
      fi
      if [[ $line ]]; then
        if [[ $QUIET == "index" ]]; then # show only the index image
          echo "$line" | sed -r -e "s#registry-proxy.engineering.redhat.com/rh-osbs/${IMAGE_PREFIX}-##" -e "s#([^\t]+)\t([^\t]+)\tv.+#\2#"
        elif [[ $QUIET == "bundle" ]]; then # show only the bundle image
          echo "$line" | sed -r -e "s#\ *([^\t]+)\t([^\t]+)\tv.+#\1#"
        else
          echo "$line" # | sed -r -e "s#registry-proxy.engineering.redhat.com/rh-osbs/${IMAGE_PREFIX}-#  #" 
        fi 
        break;
      fi
    fi
    (( count=count+1 ))
    sleep 300s
  done
    # or report an error
    if [[ !$? -eq 0 ]]; then
        echo "[ERROR] Did not get IIBs after ${this_timeout} minutes - script must exit!"
        exit 1;
    fi
}

VERBOSE=0
QUIET="none"
OCP_VERSION="" # if not set, check for all available versions, and return multiple results

crwDefaults () {
  PROD_VERSION="2.15"
  PROD_NAME="CodeReady Workspaces"
  IMAGE_PREFIX="codeready-workspaces"
  CSVs="operator-metadata operator-bundle"
}

dsDefaults() {
  PROD_NAME="Dev Spaces"
  IMAGE_PREFIX="devspaces"
  CSVs="operator-bundle"
}

dwoDefaults() {
  PROD_NAME="DevWorkspace Operator"
  IMAGE_PREFIX="devworkspace"
  CSVs="operator-bundle"
}

wtoDefaults() {
  PROD_NAME="Web Terminal Operator"
  IMAGE_PREFIX="web-terminal"
  CSVs="operator-bundle"
}

dsDefaults

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-v') PROD_VERSION="$2"; shift 2;;
    '-o') OCP_VERSION="$2"; shift 2;;
    '-p') PROD_NAME="$2"; shift 2;;
    '-c') CSVs="$2"; shift 2;;
    '-i') IMAGE_PREFIX="$2"; shift 2;;
    '--verbose') VERBOSE=1; QUIET="none"; shift 1;;
    '-q'|'-qi') VERBOSE=0; QUIET="index"; shift 1;;
    '-qb') VERBOSE=0; QUIET="bundle"; shift 1;;
    '--crw') crwDefaults; shift 1;;
    '--ds')   dsDefaults; shift 1;;
    '--dwo') dwoDefaults; shift 1;;
    '--wto') wtoDefaults; shift 1;;
  esac
done

if [[ -z ${PROD_VERSION} ]]; then usage; exit 1; fi

# override for old releases
if [[ $PROD_VERSION == "2.15" ]]; then crwDefaults; fi

for csv in $CSVs; do
  runCommandWithTimeout 30
done

