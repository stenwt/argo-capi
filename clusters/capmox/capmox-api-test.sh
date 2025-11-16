# Get the values from the secret
URL=$(kubectl get secret proxmox-credentials -n capmox -o jsonpath='{.data.url}' | base64 -d)
TOKEN_ID=$(kubectl get secret proxmox-credentials -n capmox -o jsonpath='{.data.token-id}' | base64 -d)
TOKEN_SECRET=$(kubectl get secret proxmox-credentials -n capmox -o jsonpath='{.data.token-secret}' | base64 -d)

# Test the API (use -k to skip TLS verification for testing)
curl -k "${URL}/api2/json/version" \
  -H "Authorization: PVEAPIToken=${TOKEN_ID}=${TOKEN_SECRET}"
