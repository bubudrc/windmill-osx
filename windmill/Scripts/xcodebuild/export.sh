#!/bin/bash
set -e

PROJECT_NAME=$1
SCHEME=$2

xcodebuild -exportArchive -archivePath ${WIDMILL_HOME}/${PROJECT_NAME}/archive/${SCHEME}.xcarchive -exportOptionsPlist ${RESOURCES_ROOT}/exportOptions.plist -exportPath ${WIDMILL_HOME}/${PROJECT_NAME}/export -allowProvisioningUpdates
## Export 
#
#adHocProvisioningNotFound = 70 //"No matching provisioning profiles found"
