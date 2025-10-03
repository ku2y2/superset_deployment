# Keycloak SSO Setup for Apache Superset

This guide explains how to set up Single Sign-On (SSO) for Apache Superset using Keycloak as the OAuth 2.0 / OpenID Connect provider.

## Overview

This configuration enables:
- OAuth 2.0 / OpenID Connect authentication via Keycloak
- Automatic user registration from Keycloak
- Single Sign-On experience
- Keycloak running locally on port 8090
- Superset accessible on port 8081

## Prerequisites

- Docker and Docker Compose installed
- Superset deployed using `production-superset-values.yaml`
- Network connectivity between Superset and Keycloak

## Step 1: Start Keycloak

### Launch Keycloak Container

```bash
# Start Keycloak using Docker Compose
docker-compose -f docker-compose-keycloak.yaml up -d

# Check Keycloak is running
docker ps | grep keycloak

# Wait for Keycloak to be ready (takes ~60 seconds)
docker logs -f keycloak
```

### Access Keycloak Admin Console

1. Open browser: http://localhost:8090
2. Click **Administration Console**
3. Login credentials:
   - Username: `admin`
   - Password: `admin`

## Step 2: Configure Keycloak Client

### Option A: Automated Configuration (Recommended)

Use the provided script to automatically configure Keycloak:

```bash
# Run the configuration script
./configure-keycloak.sh

# Or with custom port
./configure-keycloak.sh --port 8081

# To only update redirect URIs later
./configure-keycloak.sh --update --port 8082
```

This script will:
- Create the Superset client with correct settings
- Generate and display the client secret
- Create a test user (testuser/password)
- Save credentials to `keycloak-credentials.txt`

### Option B: Manual Configuration

1. In Keycloak Admin Console, select **Clients** from left menu
2. Click **Create client**
3. Configure General Settings:
   - **Client type**: OpenID Connect
   - **Client ID**: `superset`
   - Click **Next**

4. Configure Capability:
   - **Client authentication**: ON
   - **Authorization**: OFF
   - **Authentication flow**:
     - ✅ Standard flow
     - ✅ Direct access grants
   - Click **Next**

5. Configure Login Settings:
   - **Valid redirect URIs**:
     ```
     http://localhost:8081/*
     http://localhost:8081/oauth-authorized/keycloak
     ```
   - **Valid post logout redirect URIs**: `http://localhost:8081/*`
   - **Web origins**: `http://localhost:8081`
   - Click **Save**

### Get Client Secret

1. Go to **Clients** → **superset**
2. Click **Credentials** tab
3. Copy the **Client Secret** value
4. Save this for the next step

## Step 3: Configure Superset Environment Variables

### Option A: Using Kubernetes Secrets (Recommended for Production)

```bash
# Create Kubernetes secret with Keycloak credentials
kubectl create secret generic superset-keycloak \
  --from-literal=KEYCLOAK_CLIENT_ID=superset \
  --from-literal=KEYCLOAK_CLIENT_SECRET=<your-client-secret> \
  --from-literal=KEYCLOAK_DOMAIN=host.docker.internal:8090 \
  -n production

# Update deployment to use secret
kubectl set env deployment/superset --from=secret/superset-keycloak -n production
```

### Option B: Update Helm Values (Development/Testing)

Edit `production-superset-values.yaml` and update the Keycloak configuration:

```yaml
extraEnv:
  KEYCLOAK_CLIENT_ID: "superset"
  KEYCLOAK_CLIENT_SECRET: "your-client-secret-here"
  KEYCLOAK_DOMAIN: "host.docker.internal:8090"  # For Docker Desktop
  # Or use "localhost:8090" depending on your setup
```

Then upgrade the Helm release:

```bash
helm upgrade superset superset/superset \
  --namespace production \
  --values production-superset-values.yaml
```

## Step 4: Create Keycloak Users

### Create Test User

If you used the automated script (`configure-keycloak.sh`), a test user is already created. Otherwise, create one manually:

1. In Keycloak Admin Console, go to **Users**
2. Click **Add user**
3. Fill in user details:
   - **Username**: testuser
   - **Email**: testuser@example.com
   - **First name**: Test
   - **Last name**: User
   - **Email verified**: ON
   - Click **Create**

4. Set user password:
   - Go to **Credentials** tab
   - Click **Set password**
   - Enter password (e.g., `password`)
   - **Temporary**: OFF
   - Click **Save**

## Step 5: Test SSO Login

### Access Superset

1. Open browser: http://localhost:8081
2. You should see a **Login with Keycloak** button
3. Click the button
4. You'll be redirected to Keycloak login page
5. Enter credentials:
   - Username: `testuser`
   - Password: `password`
6. After successful authentication, you'll be redirected back to Superset

### Verify User Registration

```bash
# Check Superset logs for user creation
kubectl logs -f deployment/superset -n production | grep -i "user\|oauth\|keycloak"
```

## Configuration Details

### OAuth Endpoints

The configuration in `production-superset-values.yaml` uses these Keycloak endpoints:

- **Authorization URL**: `http://localhost:8090/realms/master/protocol/openid-connect/auth`
- **Token URL**: `http://host.docker.internal:8090/realms/master/protocol/openid-connect/token`
- **API Base URL**: `http://host.docker.internal:8090/realms/master/protocol/openid-connect`
- **Metadata URL**: `http://host.docker.internal:8090/realms/master/.well-known/openid-configuration`

**Note**: The authorization URL uses `localhost:8090` (browser-accessible), while token/API URLs use `host.docker.internal:8090` (pod-to-container communication).

### User Registration Settings

```python
AUTH_TYPE = AUTH_OAUTH
AUTH_USER_REGISTRATION = True
AUTH_USER_REGISTRATION_ROLE = "Public"
```

- Users are automatically registered on first login
- Default role: **Public** (change to "Gamma" or "Alpha" for more permissions)

### Scopes

The OAuth provider requests these scopes:
- `openid` - Required for OpenID Connect
- `email` - User email address
- `profile` - User profile information (name, etc.)

## Troubleshooting

### Issue: "Redirect URI mismatch"

**Solution**: Verify redirect URIs in Keycloak client settings match exactly:
```
http://localhost:8081/*
http://localhost:8081/oauth-authorized/keycloak
```

### Issue: "Cannot connect to Keycloak"

**Solution**: Check network connectivity:

```bash
# From within Superset pod
kubectl exec -it deployment/superset -n production -- curl http://host.docker.internal:8090/realms/master/.well-known/openid-configuration
```

If using Minikube or specific Docker setups, you may need to use:
- `host.docker.internal:8090` (Docker Desktop on Mac/Windows)
- `172.17.0.1:8090` (Docker on Linux)
- `host.minikube.internal:8090` (Minikube)

### Issue: "User registered but no permissions"

**Solution**: Update the default role in `production-superset-values.yaml`:

```python
AUTH_USER_REGISTRATION_ROLE = "Gamma"  # Change from "Public" to "Gamma"
```

Then upgrade Superset deployment.

### Issue: "authlib module not found"

**Solution**: The `bootstrapScript` should install authlib automatically. Verify:

```bash
kubectl exec -it deployment/superset -n production -- python -c "import authlib; print(authlib.__version__)"
```

If not installed, manually install:

```bash
kubectl exec -it deployment/superset -n production -- pip install authlib
```

### Debug OAuth Flow

Enable debug logging in Superset:

```bash
# Check Superset logs during login attempt
kubectl logs -f deployment/superset -n production

# Check init job logs
kubectl logs job/superset-init-db -n production
```

## Advanced Configuration

### Using Custom Realm

To use a realm other than `master`, update URLs in `production-superset-values.yaml`:

```python
OAUTH_PROVIDERS = [
    {
        "name": "keycloak",
        "icon": "fa-key",
        "token_key": "access_token",
        "remote_app": {
            "client_id": os.environ.get("KEYCLOAK_CLIENT_ID", "superset"),
            "client_secret": os.environ.get("KEYCLOAK_CLIENT_SECRET", ""),
            "api_base_url": f"http://{os.environ.get('KEYCLOAK_DOMAIN', 'host.docker.internal:8090')}/realms/YOUR_REALM/protocol/openid-connect",
            # ... update other URLs to use YOUR_REALM
        }
    }
]
```

### Custom Security Manager

For advanced user mapping and role assignment, create a custom security manager:

```python
# custom_sso_security_manager.py
from superset.security import SupersetSecurityManager

class CustomSsoSecurityManager(SupersetSecurityManager):
    def oauth_user_info(self, provider, response=None):
        if provider == "keycloak":
            me = self.appbuilder.sm.oauth_remotes[provider].get("userinfo")
            data = me.json()
            return {
                "username": data.get("preferred_username"),
                "email": data.get("email"),
                "first_name": data.get("given_name"),
                "last_name": data.get("family_name"),
                "role_keys": data.get("roles", []),  # Map Keycloak roles to Superset roles
            }
```

Then update `production-superset-values.yaml`:

```python
from custom_sso_security_manager import CustomSsoSecurityManager
CUSTOM_SECURITY_MANAGER = CustomSsoSecurityManager
```

## Kubernetes External Service (Optional)

To access Keycloak from Kubernetes pods, deploy the external service:

```bash
# The docker-compose-keycloak.yaml file includes a Kubernetes service definition
# Extract and apply only the Kubernetes section:
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keycloak-external
  namespace: production
spec:
  type: ExternalName
  externalName: host.docker.internal
  ports:
    - port: 8090
      targetPort: 8090
      protocol: TCP
EOF
```

## Stopping Keycloak

```bash
# Stop Keycloak container
docker-compose -f docker-compose-keycloak.yaml down

# Stop and remove volumes (WARNING: deletes all Keycloak data)
docker-compose -f docker-compose-keycloak.yaml down -v
```

## Production Considerations

For production deployments:

1. **Use HTTPS**: Configure Keycloak and Superset with SSL/TLS certificates
2. **Change Default Credentials**: Update Keycloak admin password
3. **Use Kubernetes Secrets**: Store client secrets securely
4. **Deploy Keycloak in Kubernetes**: For high availability and persistence
5. **Configure CORS Properly**: Restrict origins to your domain
6. **Set Up Backup**: Regular backups of Keycloak database
7. **Use Production Realm**: Don't use `master` realm for applications
8. **Enable MFA**: Configure multi-factor authentication in Keycloak
9. **Monitor Logs**: Set up logging and monitoring for OAuth flows
10. **Regular Updates**: Keep Keycloak and Superset updated

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Flask-AppBuilder OAuth Documentation](https://flask-appbuilder.readthedocs.io/en/latest/security.html#authentication-oauth)
- [Superset Authentication Documentation](https://superset.apache.org/docs/security/)
- [OpenID Connect Specification](https://openid.net/connect/)
