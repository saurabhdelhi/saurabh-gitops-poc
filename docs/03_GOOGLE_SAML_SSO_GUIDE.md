# Google Workspace SAML 2.0 SSO Integration for Argo CD

This guide walks you through migrating from default Google OAuth/SSO to **Google Workspace SAML 2.0 with Group-Based RBAC**.

---

## Why Switch from Google OAuth to Google SAML 2.0?

| Feature | Google OAuth 2.0 / OIDC | Google Workspace SAML 2.0 |
| :--- | :--- | :--- |
| **User Authentication** | Supported | Supported |
| **Group Claims (RBAC)** | Requires Google Service Account with Directory API Domain-Wide Delegation | **Native SAML Attribute Mapping** (Groups are passed directly in the SAML assertion without Service Account keys) |
| **Enterprise Governance** | User-consented or Client ID scoped | Centrally managed as an Enterprise SAML App in Google Admin Console |
| **Security Auditing** | Standard OAuth token logging | Detailed SAML audit events in Google Admin Reports |

---

## Step 1: Configure Custom SAML App in Google Workspace

1. Log in to [Google Workspace Admin Console](https://admin.google.com/) with an administrator account.
2. Go to **Apps** > **Web and mobile apps**.
3. Click **Add App** > **Add custom SAML app**.
4. **App details**:
   - **App name**: `Argo CD`
   - **Description**: `GitOps Continuous Delivery Platform`
   - (Optional) Upload an ArgoCD logo. Click **Continue**.

---

## Step 2: Download Google IdP Metadata & Certificate

Under **Google Identity Provider details**:
1. Copy the **SSO URL** (format: `https://accounts.google.com/o/saml2/idp?idpid=XXXXX`).
2. Copy the **Entity ID** (format: `https://accounts.google.com/o/saml2?idpid=XXXXX`).
3. Download the **Certificate (CRT/PEM)** and save it as `GoogleIDPCertificate.pem`.
4. Click **Continue**.

---

## Step 3: Configure Service Provider (Argo CD) Details

In the **Service provider details** screen:

| Field | Value | Notes |
| :--- | :--- | :--- |
| **ACS URL** | `https://argocd.yourcompany.com/api/dex/callback` | Assertion Consumer Service endpoint. |
| **Entity ID** | `https://argocd.yourcompany.com/api/dex/callback` | Unique identifier (must match `entityIssuer` in Dex). |
| **Start URL** | `https://argocd.yourcompany.com` | Redirect destination after login. |
| **Signed Response** | Check the box (Enabled) | Ensures SAML response signature verification. |
| **Name ID Format** | `EMAIL` | Sends email address in the Subject. |
| **Name ID** | `Basic Information > Primary email` | Maps user's primary corporate email. |

Click **Continue**.

---

## Step 4: Map SAML Attributes & Google Groups (Crucial!)

This step maps Google user and group data into SAML assertion claims that Dex will read.

1. **User Attributes**:
   - Under **Google directory attributes**, select `Basic Information > Primary email` -> Enter App attribute: `email`.
   - Select `Basic Information > First name` -> Enter App attribute: `name`.

2. **Group Membership**:
   - Under **Group membership (optional)**:
   - Search and select your corporate groups:
     - `devops-team@yourcompany.com`
     - `engineering-all@yourcompany.com`
     - `security-auditors@yourcompany.com`
   - Set the App attribute name to: `groups`

> [!IMPORTANT]
> Google Workspace **does not send all groups by default**. You **must** explicitly select which groups to include in the SAML assertion. If you miss this, user logins will succeed, but users will only receive the default fallback role because the `groups` claim will be empty!

3. Click **Finish**.

---

## Step 5: Enable the SAML App for Users

1. By default, newly created SAML apps are **OFF for everyone**.
2. In the app overview, click **User access**.
3. Set **Service status** to **ON for everyone** (or restrict to specific Organizational Units / OUs).
4. Click **Save**.

---

## Step 6: Encode Certificate & Update Argo CD Helm Values

Convert the downloaded certificate into base64 format (single line):

```bash
# macOS:
base64 -i GoogleIDPCertificate.pem | tr -d '\n'
```

Update `argocd-infra/helm/values-saml-google.yaml` with your actual values:
- `ssoURL`: Your Google SSO URL
- `ssoIssuer`: Your Google Entity ID
- `caData`: Output from the base64 command above
- `redirectURI` & `entityIssuer`: Your ArgoCD domain

Deploy the configuration using Helm:

```bash
helm upgrade --install argocd argo-cd/argo-cd \
  --namespace argocd \
  -f argocd-infra/helm/values-production.yaml \
  -f argocd-infra/helm/values-saml-google.yaml
```

---

## Step 7: Verification & Troubleshooting

### 1. Check Dex Logs for SAML Handshake
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-dex-server -f
```
Expected output upon clicking **LOG IN VIA GOOGLE WORKSPACE**:
```
connector "google" selected
redirecting to SAML IdP: https://accounts.google.com/o/saml2/idp?idpid=...
SAML callback received for user: saurabh.sharma@yourcompany.com
groups extracted: ["devops-team@yourcompany.com"]
```

### 2. Check ArgoCD RBAC Evaluation
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f
```
Inspect if user claims match the RBAC policies defined in `argocd-rbac-cm`.

### 3. Test using ArgoCD CLI
```bash
argocd login argocd.yourcompany.com --sso
argocd account can-i sync applications '*'
# Should return 'yes' for admin/developer roles
```

---

## Common Production Issues & Resolutions

| Issue | Root Cause | Solution |
| :--- | :--- | :--- |
| **`Invalid SAML response: signature verification failed`** | `caData` certificate mismatch or expired X.509 cert. | Re-download IdP certificate from Google Admin and verify base64 encoding has no unexpected newlines. |
| **User logs in but sees no applications (Read-only)** | Group name mismatch or groups not mapped in Google Admin. | Verify groups in Google Admin Console under SAML App > Attribute Mapping > Group Membership. Ensure exact email casing matches `policy.csv`. |
| **`403 app_not_configured_for_user`** | App is not turned ON for user's OU in Google Admin. | Go to Google Admin > Web & Mobile Apps > Argo CD > User Access > Change to **ON for everyone**. (Can take 5-10 mins to propagate). |
| **Redirect loop or `invalid_grant`** | ACS URL in Google Admin doesn't match `redirectURI` in Dex. | Ensure both match `https://<argocd-domain>/api/dex/callback` exactly including protocol (`https`). |
