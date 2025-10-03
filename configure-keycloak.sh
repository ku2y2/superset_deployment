#!/bin/bash

# Keycloak Configuration Script for Superset SSO
# This script uses Keycloak Admin REST API to configure a client for Superset
# Supports both initial setup and updating redirect URIs

KEYCLOAK_URL="http://localhost:8090"
ADMIN_USER="admin"
ADMIN_PASSWORD="admin"
REALM="master"
CLIENT_ID="superset"

# Parse command line arguments
UPDATE_MODE=false
REDIRECT_PORT="8082"

while [[ $# -gt 0 ]]; do
  case $1 in
    --update)
      UPDATE_MODE=true
      shift
      ;;
    --port)
      REDIRECT_PORT="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --update         Add redirect URIs without removing existing ones"
      echo "  --port PORT      Set redirect URI port (default: 8082)"
      echo "  --help           Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                      # Full setup with default port 8082"
      echo "  $0 --port 8081          # Full setup with port 8081"
      echo "  $0 --update --port 8082 # Add redirect URIs for port 8082 (preserves existing)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

if [ "$UPDATE_MODE" = true ]; then
  echo "============================================"
  echo "Updating Keycloak Redirect URIs"
  echo "============================================"
  echo ""
  echo "Target port: ${REDIRECT_PORT}"
  echo ""
else
  echo "============================================"
  echo "Configuring Keycloak for Superset SSO"
  echo "============================================"
  echo ""
  echo "Redirect URI port: ${REDIRECT_PORT}"
  echo ""
fi

# Step 1: Get admin access token
if [ "$UPDATE_MODE" = true ]; then
  echo "[1/2] Getting admin access token..."
else
  echo "[1/5] Getting admin access token..."
fi
ACCESS_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASSWORD}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
  echo "❌ Failed to get access token. Make sure Keycloak is running on ${KEYCLOAK_URL}"
  exit 1
fi
echo "✅ Got access token"
echo ""

# Get client UUID (needed for both modes)
CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" | jq -r ".[] | select(.clientId==\"${CLIENT_ID}\") | .id")

if [ "$UPDATE_MODE" = true ]; then
  # UPDATE MODE: Add redirect URIs without removing existing ones
  echo "[2/2] Adding redirect URIs to existing configuration..."

  if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" == "null" ]; then
    echo "❌ Client '${CLIENT_ID}' not found. Run without --update to create it first."
    exit 1
  fi

  # Get existing client configuration
  EXISTING_CONFIG=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLIENT_UUID}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json")

  # Extract existing redirect URIs and web origins
  EXISTING_REDIRECTS=$(echo "$EXISTING_CONFIG" | jq -r '.redirectUris[]' 2>/dev/null)
  EXISTING_ORIGINS=$(echo "$EXISTING_CONFIG" | jq -r '.webOrigins[]' 2>/dev/null)

  # Build new redirect URIs array (existing + new)
  NEW_REDIRECTS='[
    "http://localhost:'"${REDIRECT_PORT}"'/*",
    "http://localhost:'"${REDIRECT_PORT}"'/oauth-authorized/keycloak",
    "http://localhost:'"${REDIRECT_PORT}"'/oauth-authorized/keycloak/*"'

  # Add existing redirects if they don't match the new ones
  while IFS= read -r uri; do
    if [ ! -z "$uri" ] && [ "$uri" != "null" ]; then
      # Skip if it's already in our new list
      if [[ ! "$uri" =~ "http://localhost:${REDIRECT_PORT}" ]]; then
        NEW_REDIRECTS="$NEW_REDIRECTS,"'
    "'"$uri"'"'
      fi
    fi
  done <<< "$EXISTING_REDIRECTS"

  NEW_REDIRECTS="$NEW_REDIRECTS"'
  ]'

  # Build new web origins array (existing + new)
  NEW_ORIGINS='[
    "http://localhost:'"${REDIRECT_PORT}"'",
    "*"'

  # Add existing origins if they don't match the new ones
  while IFS= read -r origin; do
    if [ ! -z "$origin" ] && [ "$origin" != "null" ] && [ "$origin" != "*" ]; then
      # Skip if it's already in our new list
      if [[ ! "$origin" =~ "http://localhost:${REDIRECT_PORT}" ]]; then
        NEW_ORIGINS="$NEW_ORIGINS,"'
    "'"$origin"'"'
      fi
    fi
  done <<< "$EXISTING_ORIGINS"

  NEW_ORIGINS="$NEW_ORIGINS"'
  ]'

  # Update client with merged configuration
  curl -s -X PUT "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLIENT_UUID}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "clientId": "'"${CLIENT_ID}"'",
      "redirectUris": '"${NEW_REDIRECTS}"',
      "webOrigins": '"${NEW_ORIGINS}"'
    }'

  echo "✅ Redirect URIs added successfully (existing ones preserved)!"
  echo ""
  echo "Added redirect URIs:"
  echo "  - http://localhost:${REDIRECT_PORT}/*"
  echo "  - http://localhost:${REDIRECT_PORT}/oauth-authorized/keycloak"
  echo "  - http://localhost:${REDIRECT_PORT}/oauth-authorized/keycloak/*"
  echo ""
  echo "ℹ️  Existing URIs were preserved. View all URIs in Keycloak Admin Console."
  echo ""
  exit 0
fi

# FULL SETUP MODE
# Step 2: Check if client already exists
echo "[2/5] Checking if Superset client already exists..."

if [ ! -z "$CLIENT_UUID" ] && [ "$CLIENT_UUID" != "null" ]; then
  echo "⚠️  Client '${CLIENT_ID}' already exists. Deleting it first..."
  curl -s -X DELETE "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLIENT_UUID}" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}"
  echo "✅ Deleted existing client"
fi
echo ""

# Step 3: Create Superset client
echo "[3/5] Creating Superset client..."
CREATE_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "'"${CLIENT_ID}"'",
    "name": "Apache Superset",
    "description": "Apache Superset SSO Client",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "redirectUris": [
      "http://localhost:'"${REDIRECT_PORT}"'/*",
      "http://localhost:'"${REDIRECT_PORT}"'/oauth-authorized/keycloak"
    ],
    "webOrigins": [
      "http://localhost:'"${REDIRECT_PORT}"'"
    ],
    "protocol": "openid-connect",
    "publicClient": false,
    "standardFlowEnabled": true,
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": false
  }')

echo "✅ Created Superset client"
echo ""

# Step 4: Get client secret
echo "[4/5] Getting client secret..."
sleep 2  # Wait for client to be fully created
CLIENT_UUID=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" | jq -r ".[] | select(.clientId==\"${CLIENT_ID}\") | .id")

if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" == "null" ]; then
  echo "❌ Failed to get client UUID"
  exit 1
fi

CLIENT_SECRET=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLIENT_UUID}/client-secret" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.value')

if [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" == "null" ]; then
  echo "❌ Failed to get client secret"
  exit 1
fi

echo "✅ Got client secret"
echo ""

# Step 5: Create test user
echo "[5/5] Creating test user..."
USER_EXISTS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/users?username=testuser" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.[0].id')

if [ ! -z "$USER_EXISTS" ] && [ "$USER_EXISTS" != "null" ]; then
  echo "⚠️  User 'testuser' already exists. Skipping user creation."
else
  curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/users" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
      "username": "testuser",
      "email": "testuser@example.com",
      "firstName": "Test",
      "lastName": "User",
      "enabled": true,
      "emailVerified": true,
      "credentials": [{
        "type": "password",
        "value": "password",
        "temporary": false
      }]
    }'
  echo "✅ Created test user (testuser/password)"
fi
echo ""

# Display configuration summary
echo "============================================"
echo "✅ Keycloak Configuration Complete!"
echo "============================================"
echo ""
echo "📋 Configuration Summary:"
echo "  Keycloak URL: ${KEYCLOAK_URL}"
echo "  Realm: ${REALM}"
echo "  Client ID: ${CLIENT_ID}"
echo "  Client Secret: ${CLIENT_SECRET}"
echo ""
echo "👤 Test User Credentials:"
echo "  Username: testuser"
echo "  Password: password"
echo ""
echo "🔐 Admin Credentials:"
echo "  URL: ${KEYCLOAK_URL}"
echo "  Username: ${ADMIN_USER}"
echo "  Password: ${ADMIN_PASSWORD}"
echo ""
echo "📝 Next Steps:"
echo "  1. Create Kubernetes secret with these credentials:"
echo ""
echo "     kubectl create secret generic superset-keycloak \\"
echo "       --from-literal=KEYCLOAK_CLIENT_ID=${CLIENT_ID} \\"
echo "       --from-literal=KEYCLOAK_CLIENT_SECRET=${CLIENT_SECRET} \\"
echo "       --from-literal=KEYCLOAK_DOMAIN=host.docker.internal:8090 \\"
echo "       -n superset-sso"
echo ""
echo "  2. Deploy Superset with SSO enabled"
echo ""
echo "============================================"

# Save credentials to file
cat > keycloak-credentials.txt <<EOF
Keycloak Configuration for Superset
====================================

Keycloak URL: ${KEYCLOAK_URL}
Realm: ${REALM}
Client ID: ${CLIENT_ID}
Client Secret: ${CLIENT_SECRET}

Test User:
  Username: testuser
  Password: password

Admin Access:
  URL: ${KEYCLOAK_URL}
  Username: ${ADMIN_USER}
  Password: ${ADMIN_PASSWORD}

Kubernetes Secret Command:
  kubectl create secret generic superset-keycloak \\
    --from-literal=KEYCLOAK_CLIENT_ID=${CLIENT_ID} \\
    --from-literal=KEYCLOAK_CLIENT_SECRET=${CLIENT_SECRET} \\
    --from-literal=KEYCLOAK_DOMAIN=host.docker.internal:8090 \\
    -n superset-sso
EOF

echo "💾 Credentials saved to: keycloak-credentials.txt"
echo ""
