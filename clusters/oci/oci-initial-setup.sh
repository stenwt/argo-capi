#!/usr/bin/env bash
# --------------------------------------------------------------
#  OCI – OKE CAPI bootstrap script
#  Creates:
#   • user  (oke-user)
#   • group (oke-group) and adds the user to the group
#   • four policies with the requested permissions
#   • an RSA API key for the user and prints the useful IDs
#
#  BEFORE RUNNING:
#   • Install & configure OCI CLI (oci setup config)
#   • Have a tenancy OCID and a compartment OCID ready
#   • Run as a user that can manage Identity resources
# --------------------------------------------------------------

set -euo pipefail

# -----------------------------------------------------------------
#  USER‑CONFIGURABLE SETTINGS –‑‑‑‑‑‑‑‑‑‑‑‑‑
# ------------------------------------------------------------------
# Replace these two values with your own tenancy / compartment OCIDs
TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaaXXXXXXXXXXXXXXXXXXXXXX"
COMPARTMENT_OCID="${TENANCY_OCID}"   # change if you want a child compartment

# Names (feel free to edit)
USER_NAME="oke-user"
GROUP_NAME="oke-group"

# Where to store the temporary RSA key pair (will be created in the cwd)
KEY_DIR="$(pwd)/oke_user_keys"
PRIVATE_KEY_PATH="${KEY_DIR}/oke_user_private_key.pem"
PUBLIC_KEY_PATH="${KEY_DIR}/oke_user_public_key.pem"

# ------------------------------------------------------------------
#  HELPER FUNCTIONS
# ------------------------------------------------------------------
log() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# -----------------------------------------------------------------
#  PREPARE KEY DIRECTORY
# ------------------------------------------------------------------
mkdir -p "${KEY_DIR}"
chmod 700 "${KEY_DIR}"

# ------------------------------------------------------------------
#  1️⃣ CREATE THE USER
# ------------------------------------------------------------------
log "Creating user '${USER_NAME}' ..."
USER_OCID=$(oci iam user create \
    --name "${USER_NAME}" \
    --description "User for OKE CAPI automation" \
    --query 'data.id' \
    --raw-output)
log "User created – OCID: ${USER_OCID}"

# ------------------------------------------------------------------
#  2️⃣ CREATE THE GROUP
# ------------------------------------------------------------------
log "Creating group '${GROUP_NAME}' ..."
GROUP_OCID=$(oci iam group create \
    --name "${GROUP_NAME}" \
    --description "Group for OKE CAPI automation" \
    --query 'data.id' \
    --raw-output)
log "Group created – OCID: ${GROUP_OCID}"

# ------------------------------------------------------------------
#  3️⃣ ADD USER TO GROUP
# ---------------------------------------------------------------
log "Adding user to group ..."
oci iam group add-user \
    --group-id "${GROUP_OCID}" \
    --user-id "${USER_OCID}"
log "User added to group."

# ------------------------------------------------------------------
#  4️⃣ CREATE POLICIES
# ------------------------------------------------------------------
declare -a POLICY_DESCRIPTIONS=(
    "Allow group ${GROUP_NAME} to manage dynamic-groups"
    "Allow group ${GROUP_NAME} to manage virtual-network-family in compartment ${COMPARTMENT_OCID}"
    "Allow group ${GROUP_NAME} to manage cluster-family in compartment ${COMPARTMENT_OCID}"
    "Allow group ${GROUP_NAME} to manage instance-family in compartment ${COMPARTMENT_OCID}"
)

declare -a POLICY_STATEMENTS=(
    "Allow group ${GROUP_NAME} to manage dynamic-groups"
    "Allow group ${GROUP_NAME} to manage virtual-network-family in compartment ${COMPARTMENT_OCID}"
    "Allow group ${GROUP_NAME} to manage cluster-family in compartment ${COMPARTMENT_OCID}"
    "Allow group ${GROUP_NAME} to manage instance-family in compartment ${COMPARTMENT_OCID}"
)

for idx in "${!POLICY_DESCRIPTIONS[@]}"; do
    DESC="${POLICY_DESCRIPTIONS[$idx]}"
    STMT="${POLICY_STATEMENTS[$idx]}"
    POLICY_NAME="oke-${GROUP_NAME}-${idx}"

    log "Creating policy '${POLICY_NAME}' – ${DESC}"
    oci iam policy create \
        --name "${POLICY_NAME}" \
        --description "${DESC}" \
        --compartment-id "${COMPARTMENT_OCID}" \
        --statements "[\"${STMT}\"]" > /dev/null
done
log "All policies created."

# ------------------------------------------------------------------
#  5️⃣ GENERATE RSA KEY PAIR FOR THE USER
# ------------------------------------------------------------------
log "Generating RSA key pair (2048‑bit) ..."
openssl genrsa -out "${PRIVATE_KEY_PATH}" 2048 2>/dev/null
chmod 600 "${PRIVATE_KEY_PATH}"
openssl rsa -pubout -in "${PRIVATE_KEY_PATH}" -out "${PUBLIC_KEY_PATH}" 2>/dev/null
log "Key pair written to ${KEY_DIR}"

# ------------------------------------------------------------------
#  6️⃣ UPLOAD PUBLIC KEY AS AN API KEY FOR THE USER
# ------------------------------------------------------------------
log "Uploading public key as API key for user ..."
UPLOAD_OUTPUT=$(oci iam user api-key upload \
    --user-id "${USER_OCID}" \
    --key-file "${PUBLIC_KEY_PATH}" \
    --output json)

# Extract the fingerprint from the upload response
FINGERPRINT=$(echo "${UPLOAD_OUTPUT}" | jq -r '.data.fingerprint')
log "API key uploaded – fingerprint: ${FINGERPRINT}"

# ------------------------------------------------------------------
#  7️⃣ READ PRIVATE KEY CONTENT (so we can print it)
# --------------------------------------------------------
PRIVATE_KEY_CONTENT=$(cat "${PRIVATE_KEY_PATH}")

# ------------------------------------------------------------------
#  8️⃣ PRINT THE REQUESTED INFORMATION
# ------------------------------------------------------------------
log "------------------------------------------------------------"
log "✅  Script finished – here is the data you asked for:"
echo ""
echo "Compartment OCID : ${COMPARTMENT_OCID}"
echo "Tenancy OCID     : ${TENANCY_OCID}"
echo "User OCID        : ${USER_OCID}"
echo "API‑key fingerprint : ${FINGERPRINT}"
echo ""
echo "----- BEGIN PRIVATE KEY (PEM) -----"
echo "${PRIVATE_KEY_CONTENT}"
echo "----- END PRIVATE KEY (PEM) -----"
echo ""
log "Keep the private key safe – it is the only secret that lets"
log "the user authenticate via the OCI API."
log "------------------------------------------------------------"
